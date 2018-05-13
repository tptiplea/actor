const SERVER_URL = "http://localhost:3000";  // TODO: add the server URL here
const MY_UNIQUE_ID = make_random_id(10);


//* CONSTANTS **////
const SERVER_TO_PEER_KIND = 'SERVER_TO_PEER';
const PEER_TO_SERVER_KIND = 'PEER_TO_SERVER';
const PEER_TO_PEER_KIND = 'PEER_TO_PEER';
const REGISTER_UNXISOCKET_OP = 'REGISTER_UNIXSOCKET';
const UNREGISTER_UNIXSOCKET_OP = 'UNREGISTER_UNIXSOCKET';
const SERVER_PEER_TO_PEER_OP = 'PEER_TO_PEER_OP_SERVER';
const MSG_PEER_TO_PEER_OP = 'MSG_PEER_TO_PEER_OP';
const CONNECTION_OP = 'CONNECTION_OP';
const ACK_OP = 'ACK_OPERATION';
const OK_STATUS = 'SUCCESS';
const FAIL_STATUS = 'FAIL';

//****************///


////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
var TOTAL_MESSAGES_SENT = 0;
const CONNECTED_TO_SERVER_PROMISE_NAME = "connected_to_server_promise";
var unixsocket_ids_dict = {}; // keep track of unixsocket ids bound on this server
var promise_dict = {}; // keep track of promises
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************

// Connect to server.
var iosocket = io(SERVER_URL);
iosocket.on('server_to_peer', process_msg_from_server);

// The semaphore that tells us whether we're connected to the server.
create_promise(CONNECTED_TO_SERVER_PROMISE_NAME, 5 * 60 * 1000); // Timeout if we don't connect to server in that time.
get_existing_promise(CONNECTED_TO_SERVER_PROMISE_NAME).then(function (_) {
    console.log('CONNECTED TO IO SERVER, got id:', MY_UNIQUE_ID);
});


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {IOSOCKET send stuff ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
// Send a msg to server, return a promise after that is done.
function send_msg_to_server(msg) {
    return get_existing_promise(CONNECTED_TO_SERVER_PROMISE_NAME).then(function (_) {
        iosocket.emit('peer_to_server', msg);
    });
}
/** ------------------------------------------------ IOSOCKET send stuff} ------------------------------- */



/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {IOSOCKET receive stuff ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
function process_msg_from_server(msg) {
    if (msg.kind === SERVER_TO_PEER_KIND) {
        // A message from the server.

        if (msg.operation === REGISTER_UNXISOCKET_OP || msg.operation === UNREGISTER_UNIXSOCKET_OP) {
            // The result of (un)register operation.
            var result = msg.result;
            var unixsocket_id = msg.unixsocket_id;
            var promise_name =
                msg.operation === REGISTER_UNXISOCKET_OP ? promise_name_for_register_unixsocket_id(unixsocket_id)
                    : promise_name_for_unregister_unixsocket_id(unixsocket_id);
            if (result === OK_STATUS) {
                resolve_promise(promise_name, OK_STATUS);
            }
            else {
                reject_promise(promise_name, msg.error_msg);
            }

        } else if (msg.operation === CONNECTION_OP) {
            // Successfully connected to server.
            resolve_promise(CONNECTED_TO_SERVER_PROMISE_NAME)
        } else if (msg.operation === SERVER_PEER_TO_PEER_OP) {
            if (msg.result !== OK_STATUS) {
                // Server failed to send a message to other peer, probably waitlisted.
                console.log(msg.error_msg);
            }
        } else {
            throw "Unknown SERVER_TO_PEER operation " + msg.operation;
        }

    } else if (msg.kind === PEER_TO_PEER_KIND) {
        // A message from another peer, redirected by the server.
        if (msg.operation === ACK_OP) {
            // An ack for a message from here, update the promise accordingly!.
            var msg_id = msg.msg_id;
            try {
                var promise_name = promise_name_from_msg_id_ack(msg_id);
                if (msg.result === OK_STATUS)
                    resolve_promise(promise_name, OK_STATUS);
                else
                    reject_promise(promise_name, msg['result']);
            } catch (err) {
                console.log('Ack for a non existing message probably:', err);
            }

        } else if (msg['operation'] === MSG_PEER_TO_PEER_OP) {
            var from_unixsocket_id = msg['from_unixsocket_id'];
            var to_unixsocket_id = msg['to_unixsocket_id'];
            var payload = msg['payload'];
            var msg_id = msg['msg_id'];

            process_msg_from_unixsocket(from_unixsocket_id, to_unixsocket_id, payload, msg_id);
        }

    } else {
        throw "Unknown message kind " + msg;
    }
}

/** ------------------------------------------------  IOSOCKET receive stuff} ------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ REGISTER/UNREGISTER UNIXSOCKETS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
function register_unixsocket_id(unixsocket_id) {
    if (unixsocket_id in unixsocket_ids_dict) {
        throw "Unixsocket with id " + unixsocket_id + " already bound";
    }
    unixsocket_ids_dict[unixsocket_id] = true;

    var promise_name = promise_name_for_register_unixsocket_id(unixsocket_id);
    send_msg_to_server({
        'kind': PEER_TO_SERVER_KIND,
        'operation': REGISTER_UNXISOCKET_OP,
        'unixsocket_id': unixsocket_id
    });

    return create_promise(promise_name, 10 * 1000);
}

function unregister_unixsocket_id(unixsocket_id) {
    if (!(unixsocket_id in unixsocket_ids_dict)) {
        throw "Unixsocket with id " + unixsocket_id + " not bound!";
    }
    delete unixsocket_ids_dict[unixsocket_id];

    var promise_name = promise_name_for_unregister_unixsocket_id(unixsocket_id);
    send_msg_to_server({
        'kind': PEER_TO_SERVER_KIND,
        'operation': UNREGISTER_UNIXSOCKET_OP,
        'unixsocket_id': unixsocket_id
    });

    return create_promise(promise_name, 10 * 1000);
}


/** --------------------------- REGISTER/UNREGISTER UNIXSOCKETS --------------------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ PEER_TO_PEER_MSG ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// id, from this socket, send it to
function send_ack_to_unixsocket(msg_id, from_unixsocket_id, to_unixsocket_id) {
    send_msg_to_server({
       'kind': PEER_TO_PEER_KIND,
       'operation': ACK_OP,
        'result': OK_STATUS,
        'msg_id': msg_id,
        'to_unixsocket_id': to_unixsocket_id,
        'from_unixsocket_id': from_unixsocket_id
    });
}

// TODO UPDATE
function process_msg_from_unixsocket(from_unixsocket_id, to_unixsocket_id, payload, msg_id) {
    var ack_to_unixsocket_id = from_unixsocket_id; // to other
    var ack_from_unixsocket_id = to_unixsocket_id; // from me (reverse)

    send_ack_to_unixsocket(msg_id, ack_from_unixsocket_id, ack_to_unixsocket_id);
    console.log('\n\n------------');
    console.log('Got message with id: ', msg_id);
    console.log('From unixsocket_id: ', from_unixsocket_id);
    console.log('To unixsocket_id (me):', to_unixsocket_id);
    console.log('Payload: ', payload);
    console.log('------------\n\n');
}

// TODO: correct this
function send_msg_to_unixsocket(from_unixsocket_id, to_unixsocket_id, payload) {
    var msg_id = update_msg_count_and_get_unique_id();
    send_msg_to_server({
        'kind': PEER_TO_PEER_KIND,
        'operation': MSG_PEER_TO_PEER_OP,
        'from_unixsocket_id': from_unixsocket_id,
        'to_unixsocket_id': to_unixsocket_id,
        'payload': payload,
        'msg_id': msg_id
    });
    // create the promise, but don't return it, it can be obtained from the msg id if required.
    create_promise(promise_name_from_msg_id_ack(msg_id));
    return msg_id;
}


/** ------------------------------------------------  PEER_TO_PEER_MSG ------------------------------- */



/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONDITION_VARIABLES_STUFF ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
function create_promise(name, reject_timeout) {
    reject_timeout = typeof reject_timeout !== 'undefined' ? reject_timeout : Infinity; // by default, no timeout

    var resolve_cp = null;
    var reject_cp = null;
    var promise = new Promise(function (resolve, reject) {
        resolve_cp = resolve;
        reject_cp = reject;

        // Set a timer to reject the promise on a timeout.
        if (reject_timeout < Infinity) setTimeout(reject, reject_timeout, 'TIMEOUT!');
    });

    promise_dict[name] = {
      'promise': promise,
      'resolve': resolve_cp, 'reject': reject_cp, 'status': 'pending'
    };

    return promise;
}

function get_existing_promise(name) {
    if (!(name in promise_dict)) {
        throw "Promise does not exist " + name;
    }
    return promise_dict[name].promise;
}

function resolve_promise(name, result) {
    if (!(name in promise_dict)) {
        throw "Promise does not exist " + name;
    }
    if (promise_dict[name].status === 'rejected') {
        throw "Promise was rejected!: " + name;
    }

    if (promise_dict[name].status === 'pending')
        promise_dict[name].resolve(result);
    promise_dict[name].status = 'resolved';
}

function reject_promise(name, reason) {
    if (!(name in promise_dict)) {
        throw "Promise does not exist " + name;
    }
    if (promise_dict[name].status === 'resolved') {
        throw "Promise was resolved!: " + name;
    }

    if (promise_dict[name].status === 'pending')
        promise_dict[name].reject(reason);
    promise_dict[name].status = 'rejected';
}
/** ------------------------------------------------------- CONDITION_VARIABLES_STUFF ------------------------------- */

/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {utils ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
function promise_name_for_register_unixsocket_id(unixsocket_id) {
    return "promise_register_unixsocket_id_" + unixsocket_id;
}

function promise_name_for_unregister_unixsocket_id(unixsocket_id) {
    return "promise_unregister_unixsocket_id_" + unixsocket_id;
}

function promise_name_from_msg_id_ack(msg_id) {
    return "promise_ack_for_msg_id_" + msg_id;
}

function make_random_id(len) {
    var id = "";
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for (var i = 0; i < len; i++)
        id += alphabet.charAt(Math.floor(Math.random() * alphabet.length));

    return id;
}

function update_msg_count_and_get_unique_id() {
    TOTAL_MESSAGES_SENT += 1;
    return 'peer_unique_id_' + MY_UNIQUE_ID + '_msg_num_' + TOTAL_MESSAGES_SENT + '_id_' + make_random_id(8);
}
/** ----------------------------------------------------------- {utils ------------------------------- */




// -------------------------------------------------------------- ******* TEST ******* //

function test() {
    var MY_SOCKET_ID = "peer_one_baby";
    var OTHER_SOCKET_ID = "peer_two_yeah";
    var MY_MESSAGE = "!!!HEY I AM PEEER ONEEEEEEEEEE 222211111112";

    register_unixsocket_id(MY_SOCKET_ID).then(function (_) {
        console.log('Successfully registered socket with id: ', MY_SOCKET_ID);

        console.log('About to sent message:', MY_MESSAGE);
        var msg_id = send_msg_to_unixsocket(MY_SOCKET_ID, OTHER_SOCKET_ID, MY_MESSAGE);
        console.log('Send with id:', msg_id);
        get_existing_promise(promise_name_from_msg_id_ack(msg_id)).then(function (_) {
            console.log('Got ACK for message', MY_MESSAGE, 'with id', msg_id);

        }, function (reason) {
            console.log('Failed to get ack with reason: ', reason);
        });
    }, function (reason) { console.log('Failed to register unixsocket_id', MY_SOCKET_ID, 'with reason', reason); });
}

test();

// ---------------------------------------------------------------------- TEST