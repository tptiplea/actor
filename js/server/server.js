//* CONSTANTS **////
const SERVER_TO_PEER_KIND = 'SERVER_TO_PEER';
const PEER_TO_SERVER_KIND = 'PEER_TO_SERVER';
const PEER_TO_PEER_KIND = 'PEER_TO_PEER';
const REGISTER_UNXISOCKET_OP = 'REGISTER_UNIXSOCKET';
const UNREGISTER_UNIXSOCKET_OP = 'UNREGISTER_UNIXSOCKET';
const SERVER_PEER_TO_PEER_OP = 'PEER_TO_PEER_OP_SERVER';
const CONNECTION_OP = 'CONNECTION_OP';
const ACK_OP = 'ACK_OPERATION';
const OK_STATUS = 'SUCCESS';
const FAIL_STATUS = 'FAIL';

//****************///


var app = require('http').createServer(handler);
var io = require('socket.io')(app);
const port = 3000;

app.listen(port);

function handler(req, res) {
    res.writeHead(200);
    res.end("<!doctype html><html><head><title>ss</title></head><body></body></html>");
}

console.log('Listening on port:', port);


// When a new socket is created, register its possible handshakes.
io.on('connection', function (iosocket) {
    iosocket.on('peer_to_server', function (msg) {
       process_msg_from_peer(iosocket, msg);
    });

    // Acknowledge connection!
    send_msg_to_peer(iosocket, {
       'kind': SERVER_TO_PEER_KIND,
       'operation': CONNECTION_OP,
       'result': OK_STATUS
    });
});


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ COMMUNICATE ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
function send_msg_to_peer(iosocket, msg) { // ASYNC
    iosocket.emit('server_to_peer', msg);
}

function process_msg_from_peer(iosocket, msg) {
    const kind = msg.kind;

    if (kind === PEER_TO_SERVER_KIND) {
        // This is a message from the peer, for the server.
        const operation = msg.operation;

        if (operation === REGISTER_UNXISOCKET_OP) {
            register_unixsocket(iosocket, msg.unixsocket_id);
        } else if (operation === UNREGISTER_UNIXSOCKET_OP) {
            unregister_unixsocket(iosocket, msg.unixsocket_id);
        }

    } else if (kind === PEER_TO_PEER_KIND) {
        // This is a message from the peer for another peer, server is just an intermediary.
        process_peer_to_peer_msg(iosocket, msg);
    } else {
        throw "Unsupported message kind " + kind;
    }
}
/**  -------------------------------------------- COMMUNICATE --------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ PEER TO PEER ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */

// Send a message to another unixsocket.
function process_peer_to_peer_msg(from_iosocket, msg) {
    const to_unixsocket_id = msg.to_unixsocket_id;

    if (to_unixsocket_id in unixsocket_to_iosocket) {
        const to_iosocket = unixsocket_to_iosocket[to_unixsocket_id];
        send_msg_to_peer(to_iosocket, msg); // Send message to other peer (dest).

        send_msg_to_peer(from_iosocket, { // Send a confirmation back to sender.
            'kind': SERVER_TO_PEER_KIND,
            'operation': SERVER_PEER_TO_PEER_OP,
            'result': OK_STATUS,
            'msg_id': msg.msg_id
        });
    } else {
        const error_msg = 'Error - P2P: unixsocket ' + to_unixsocket_id + ' not registered with server! Waitlisting msg';
        console.log(error_msg);

        send_msg_to_peer(from_iosocket, {
            'kind': SERVER_TO_PEER_KIND,
            'operation': SERVER_PEER_TO_PEER_OP,
            'result': FAIL_STATUS,
            'msg_id': msg.msg_id,
            'error_msg': error_msg
        });

        if (to_unixsocket_id in waitlist_for_unixsocket)
            waitlist_for_unixsocket[to_unixsocket_id].push(msg);
        else
            waitlist_for_unixsocket[to_unixsocket_id] = [msg];
    }
}
/**  -------------------------------------------- PEER TO PEER --------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ REGISTER/DEREGISTER SOCKETS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
var unixsocket_to_iosocket = {};
var iosocket_to_unixsockets = {};

// Requests to contact a unixsocket that are yet to be satisfied.
var waitlist_for_unixsocket = {};

// Register the unixsocket id.
function register_unixsocket(iosocket, unixsocket_id) {
    if (unixsocket_id in unixsocket_to_iosocket) {
        const error_msg = 'The socket with id ' + unixsocket_id + ' already registered!';
        console.log(error_msg);

        send_msg_to_peer(iosocket, {
            'kind': SERVER_TO_PEER_KIND,
            'operation': REGISTER_UNXISOCKET_OP,
            'result': FAIL_STATUS,
            'unixsocket_id': unixsocket_id,
            'error_msg': error_msg
        });
        return;
    }

    // Update the first map.
    unixsocket_to_iosocket[unixsocket_id] = iosocket;

    // Update the second map.
    if (iosocket.id in iosocket_to_unixsockets)
        iosocket_to_unixsockets[iosocket.id].push(unixsocket_id);
    else
        iosocket_to_unixsockets[iosocket.id] = [unixsocket_id];

    send_msg_to_peer(iosocket, {
        'kind': SERVER_TO_PEER_KIND,
        'operation': REGISTER_UNXISOCKET_OP,
        'result': OK_STATUS,
        'unixsocket_id': unixsocket_id
    });

    if (unixsocket_id in waitlist_for_unixsocket) {
        var queue = waitlist_for_unixsocket[unixsocket_id];
        var len = queue.length;

        for (var i = 0; i < len; i++) {
            send_msg_to_peer(iosocket, queue[i]);
        }

        delete waitlist_for_unixsocket[unixsocket_id]; // empty the waitlist
    }
}

// Unregister the unixsocket id.
function unregister_unixsocket(iosocket, unixsocket_id) {

    // Remove the unixsocket from both maps, if it's there.
    if (unixsocket_id in unixsocket_to_iosocket) {
        delete unixsocket_to_iosocket[unixsocket_id];

        if (iosocket.id in iosocket_to_unixsockets) {
            var index_of_unix = iosocket_to_unixsockets[iosocket.id].indexOf(unixsocket_id);
            if (index_of_unix > -1)
                iosocket_to_unixsockets[iosocket.id].splice(index_of_unix, 1);
        }

        send_msg_to_peer(iosocket, {
            'kind': SERVER_TO_PEER_KIND,
            'operation': UNREGISTER_UNIXSOCKET_OP,
            'result': OK_STATUS,
            'unixsocket_id': unixsocket_id
        });
    } else {
        // Otherwise, an error.
        var error_msg = 'Error - unregister_unixsocket: unixsocket ' + unixsocket_id + ' not registered with server!';
        console.log(error_msg);

        send_msg_to_peer(iosocket, {
            'kind': SERVER_TO_PEER_KIND,
            'operation': UNREGISTER_UNIXSOCKET_OP,
            'result': FAIL_STATUS,
            'unixsocket_id': unixsocket_id,
            'error_msg': error_msg
        });
    }
}
