const SERVER_URL = "";  // TODO: add the server URL here
var MY_URL = "";  // this is my url (globally) TODO : set it

// Connect to server.
var iosocket = io(SERVER_URL);

/** ------------------------------------------------ {variables ------------------------------- */
// These are condition variables on which we can wait.
var cond_var_dict = {};
var connected_to_server_cv = 'connected_to_server'; // Whether we are connected to server.

// This keeps track of messages.
var total_messages = 0;
/** ------------------------------------------------ variables} ------------------------------- */




/** ------------------------------------------------ {IOSOCKET receive stuff ------------------------------- */
// When connected to server.
iosocket.on('connected_to_server', function (data){
    cond_var_dict[connected_to_server_cv] = true;
});

// When we manage to contact unixsocket.
iosocket.on('ok_contact_unixsocket', function (data){
    // nothing for now
});

iosocket.on('fail_contact_unixsocket', function (data){
    console.log(data.error_msg); // just log for now
});

iosocket.on('from_unixsocket', function (data) { // Message from another unixsocket.
    process_msg_from_unixsocket(data);
});

function process_msg_from_unixsocket(msg) {
    if (is_key_true('is_ack', msg)) {
        // This is an ack for a message.
        cond_var_dict[msg['msg_id']] = true;
        return;
    }

}
/** ------------------------------------------------  IOSOCKET receive stuff} ------------------------------- */


/** ------------------------------------------------ {condvar ------------------------------- */
// Waits for a condition variable to be set to true in cond_var_dict.
function wait_for_cond_var(cond_var_name, max_timeout, check_every_ms) {
    max_timeout = typeof max_timeout !== 'undefined' ? max_timeout : Infinity; // Default value for max timeout to wait for cond.
    check_every_ms = typeof check_every_ms !== 'undefined' ? check_every_ms : 50; // Check every this many ms.

    if (is_key_true(cond_var_name, cond_var_dict)) {
        // Condition variable is set, can return safely.
        return max_timeout; // how much we have left.
    }

    if (max_timeout <= 0) {
        // Can no longer wait, fail.
        return -1;
    }

    // Otherwise, schedule same function to re-execute.
    //          fn name,           wake again in,   cvarname,    max_timeout then               check every ms
    setTimeout(wait_for_cond_var, check_every_ms, cond_var_name, max_timeout - check_every_ms, check_every_ms);
}

function check_cond_var(cond_var_name) {
    if ((cond_var_name in cond_var_dict) && (cond_var_dict[cond_var_name] === true)) {
        // Condition variable is set to true.
        return true;
    }
    return false;
}
/** ------------------------------------------------ condvar} ------------------------------- */


/** ------------------------------------------------ {IOSOCKET send stuff ------------------------------- */
function bind_unixsocket(unixsocket_id) {
    iosocket.emit('register_unixsocket', {'unixsocket_id': unixsocket_id});
}

function unbind_unixsocket(unixsocket_id) {
    iosocket.emit('unregister_unixsocket', {'unixsocket_id': unixsocket_id});
}

// NOTE: This does not wait for any ack.
function send_msg_to_unixsocket(from_unixsocket_id, to_unixsocket_id, msg) {
    wait_for_cond_var(connected_to_server_cv, wait_time);
    if (!check_cond_var(connected_to_server_cv)) return false; // Fail if not connected to server.


    total_messages += 1;
    var msg_id = "io@" + iosocket.id + '-fromunix_id@' + from_unixsocket_id + '^msgid-' + total_messages;

    iosocket.emit('contact_unixsocket', {
        'to_unixsocket_id': to_unixsocket_id,
        'from_unixsocket_id': from_unixsocket_id,
        'msg': msg,
        'msg_id': msg_id,
        'need_ack': true
    });

    return msg_id;
}
/** ------------------------------------------------ IOSOCKET send stuff} ------------------------------- */


/** ----------------------------------------------------------- {ZMQ ------------------------------- */

const VALID_ZMQSOCKET_KINDS = {'REQ': true, 'REP': true, 'DEALER': true, 'ROUTER': true};

class ZMQContext {
    constructor() {
        this.open_ports = {};
        this.zmq_sockets = {};
    }

    terminate() {
        if (Object.keys(this.open_ports).length !== 0) {
            throw "Trying to close context with sockets still open!!";
        }
        return;
    }

    create_socket(kind) {
        var socket = new ZMQSocket(this, kind);
        return socket;
    }

    try_set_identity(new_identity, old_identity, socket) {
        if (new_identity in this.zmq_sockets) {
            return false;
        }
        delete this.zmq_sockets[old_identity];
        this.zmq_sockets[new_identity] = socket;
        return true;
    }

    try_bind_address(url, socket) {
        if (url in this.open_ports) {
            return false;
        }
        this.open_ports[url] = socket;
        bind_unixsocket(url);  // bind this address
        return true;
    }

    unbind_url(url) {
        if (url in this.open_ports) {
            unbind_unixsocket(url);
            delete this.open_ports[url];
        }
    }
}

class ZMQSocket {

    constructor(context, kind) {
        if (!(kind in VALID_ZMQSOCKET_KINDS)) {
            throw "Invalid ZMQSocket kind" + kind;
        }

        this.context = context;
        this.kind = kind;
        this.send_high_water_mark = 10000;
        this.recv_high_water_mark = 10000;
        this.connected_to_unix_urls = [];  // socket is connected to all of these
        this.connected_to_ptr = -1;
        this.listen_on_unix_urls = []; // socket listens on all of these
        this.identity = make_random_id(200);
        while (!this.context.try_set_identity(this.identity, "", this)) {
            this.identity = make_random_id(200);
        }
        this.send_timeout = Infinity;
        this.recv_timeout = Infinity;

        this.last_operation = "none";
        this.last_peer = "none";

        this.in_queue = [];
        this.out_queue = [];
    }

    bind(addr) {
        var url = MY_URL + ':' + addr;  // a physical address
        if (!this.context.try_bind_address(url, this)) {
            throw "Invalid url " + url + " already bound!";
        }
        this.listen_on_unix_urls.push(url);
    }

    connect(url) {
        // for now just keep track of it.
        this.connected_to_unix_urls.push(url);

        // Create a random address to listen on.
        var addr = MY_URL + ':' + make_random_id(20);
        while (!this.context.try_bind_address(addr, this)) {
            addr = MY_URL + ':' + make_random_id(20);
        }
        this.listen_on_unix_urls.push(addr);
    }

    close() {
        for (var i = 0; i < this.listen_on_unix_urls.length; i++) {
            context.unbind_url(this.listen_on_unix_urls[i]);
        }
    }

    set_identity(new_identity) {
        if (!this.context.try_set_identity(new_identity, this.identity, this)) {
            throw "Invalid identity " + new_identity + " already used.";
        }
        this.identity = new_identity;
    }

    set_send_high_water_mark(high_water_mark) {
        this.send_high_water_mark = high_water_mark;
    }

    set_recv_high_water_mark(recv_water_mark) {
        this.recv_high_water_mark = recv_water_mark;
    }

    set_recv_timeout(recv_timeout) {
        this.recv_timeout = recv_timeout;
    }

    get get_send_high_water_mark() {
        return this.send_high_water_mark;
    }

    send(block, msg) {
        var to_addr = "";

        if (this.kind === 'REP') { // SERVER: Reply to a request.
            // Find which client did we get the request from.
            if (this.last_operation !== 'recv') {
                // Must follow a receive on this part, otherwise error.
                throw "On a REP Socket, SEND must be preceded by RECV, i.e. we must reply to something";
            }
            to_addr = this.last_peer;
        }

        if (this.kind === 'ROUTER') { // SERVER: Reply to a request.
            // The address must be in the message.
            if (!(('to_addr' in msg) && ('actual_msg' in msg))) {
                throw "On ROUTER Socket, SEND message must contain 'to_addr' and 'actual_msg' keys to tell where to send it to.";
            }
            to_addr = msg['to_addr'];
            msg = msg['actual_msg'];
        }

        if (this.kind === 'REQ' || this.kind === 'DEALER') { // CLIENT: Send to a server
            // Round-robin which we send to.
            if (this.kind === 'REQ' && this.last_operation === 'send') { // should have been either none or recv
                throw "On REQ Socket, cannot do SEND multiple times in a row!"; // for REQ can only alternate
            }
            if (this.connected_to_unix_urls.length === 0) {
                throw this.kind + " Socket not connected to any servers!";
            }
            this.connected_to_ptr += 1;
            this.connected_to_ptr %= this.connected_to_unix_urls.length;

            to_addr = this.connected_to_unix_urls[this.connected_to_ptr];
        }

        msg = {'from_identity': this.identity, 'payload': msg};

        this.last_operation = "send";
        this.last_peer = to_addr;

        var msg_id = send_msg_to_unixsocket(this.listen_on_unix_urls[0], to_addr, msg);
        this.out_queue.push(msg_id);
        var now_timeout = this.send_timeout;
        var max_queue_length = block ? 0 : this.send_high_water_mark; // we block either till we send, or have enough space in queue.
        // Remove those we got the ack for so far.
        while (this.out_queue.length >= max_queue_length) {
            const queued_msg_id = this.out_queue[0];
            const ack_cond_var = 'ack_for_' + queued_msg_id;
            now_timeout = wait_for_cond_var(ack_cond_var, now_timeout, 50);
            if (check_cond_var('ack_for_' + queued_msg_id)) {
                delete cond_var_dict['ack_for_' + queued_msg_id];
                this.out_queue.shift();
            } else {
                throw "TIMEOUT";
            }
        }
    }

    send_all(block, msg_list) {
        if (this.kind === 'ROUTER') {
            if (msg_list.length !== 2) {
                throw "Send_all should be list of 2, with first identity!";
            }
            this.send(block, {'to_addr': msg_list[0], 'actual_msg': msg_list[1]});
        } else {
            this.send(block, msg_list);
        }
    }

    recv(block) {
        // TODO: this stuff, with a queue!
        var from_addr = "";

        if (this.kind === 'REQ' && ) {

        }

        if (this.kind === 'ROUTER') {
            throw "Cannot do recv on ZMQ Router socket! Must do recv_all!";
        }

    }

    recv_all(block, msg_list) {

    }

}


/** ----------------------------------------------------------- ZMQ} ------------------------------- */


/** ----------------------------------------------------------- {utils ------------------------------- */
function is_key_true(key, dict) {
    return ((key in dict) && (dict[key] === true));
}

function make_random_id(len) {
    var id = "";
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for (var i = 0; i < len; i++)
        id += alphabet.charAt(Math.floor(Math.random() * alphabet.length));

    return id;
}
/** ----------------------------------------------------------- {utils ------------------------------- */