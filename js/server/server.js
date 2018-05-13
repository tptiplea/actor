//* CONSTANTS **////
const PCL_CONSTS = {
    SERVER_TO_PEER_KIND : 'SERVER_TO_PEER',
    PEER_TO_SERVER_KIND : 'PEER_TO_SERVER',
    PEER_TO_PEER_KIND : 'PEER_TO_PEER',
    REGISTER_UNIXSOCKET_OP : 'REGISTER_UNIXSOCKET',
    UNREGISTER_UNIXSOCKET_OP : 'UNREGISTER_UNIXSOCKET',
    SERVER_PEER_TO_PEER_OP : 'PEER_TO_PEER_OP_SERVER',
    MSG_PEER_TO_PEER_OP : 'MSG_PEER_TO_PEER_OP',
    CONNECTION_OP : 'CONNECTION_OP',
    ACK_OP : 'ACK_OPERATION',
    OK_STATUS : 'SUCCESS',
    FAIL_STATUS : 'FAIL'
};

//****************///

//* VARS **////
var app = require('http').createServer(handler);
var PCL_VARS = {
    IO : require('socket.io')(app),
    PORT : 3000,
    UNIXSOCKET_TO_IOSOCKET_DICT : {},
    IOSOCKET_TO_UNIXSOCKETS_DICT : {},
    WAITLIST_FOR_UNIXSOCKET_DICT : {} // Requests to contact a unixsocket that are yet to be satisfied because dest not connected yet.
};

//****************///


app.listen(PCL_VARS.PORT);

function handler(req, res) {
    res.writeHead(200);
    res.end("<!doctype html><html><head><title>ss</title></head><body></body></html>");
}

console.log('Listening on port:', PCL_VARS.PORT);


// When a new socket is created, register its possible handshakes.
PCL_VARS.IO.on('connection', function (iosocket) {
    iosocket.on('peer_to_server', function (msg) {
       process_msg_from_peer(iosocket, msg);
    });

    // Acknowledge connection!
    send_msg_to_peer(iosocket, {
       'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
       'operation': PCL_CONSTS.CONNECTION_OP,
       'result': PCL_CONSTS.OK_STATUS
    });
});


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ COMMUNICATE ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
function send_msg_to_peer(iosocket, msg) { // ASYNC
    iosocket.emit('server_to_peer', msg);
}

function process_msg_from_peer(iosocket, msg) {
    const kind = msg.kind;

    if (kind === PCL_CONSTS.PEER_TO_SERVER_KIND) {
        // This is a message from the peer, for the server.
        const operation = msg.operation;

        if (operation === PCL_CONSTS.REGISTER_UNIXSOCKET_OP) {
            register_unixsocket(iosocket, msg.unixsocket_id);
        } else if (operation === PCL_CONSTS.UNREGISTER_UNIXSOCKET_OP) {
            unregister_unixsocket(iosocket, msg.unixsocket_id);
        }

    } else if (kind === PCL_CONSTS.PEER_TO_PEER_KIND) {
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

    if (to_unixsocket_id in PCL_VARS.UNIXSOCKET_TO_IOSOCKET_DICT) {
        const to_iosocket = PCL_VARS.UNIXSOCKET_TO_IOSOCKET_DICT[to_unixsocket_id];
        send_msg_to_peer(to_iosocket, msg); // Send message to other peer (dest).

        send_msg_to_peer(from_iosocket, { // Send a confirmation back to sender.
            'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
            'operation': PCL_CONSTS.SERVER_PEER_TO_PEER_OP,
            'result': PCL_CONSTS.OK_STATUS,
            'msg_id': msg.msg_id
        });
    } else {
        const error_msg = 'Error - P2P: unixsocket ' + to_unixsocket_id + ' not registered with server! Waitlisting msg';
        console.log(error_msg);

        send_msg_to_peer(from_iosocket, {
            'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
            'operation': PCL_CONSTS.SERVER_PEER_TO_PEER_OP,
            'result': PCL_CONSTS.FAIL_STATUS,
            'msg_id': msg.msg_id,
            'error_msg': error_msg
        });

        if (to_unixsocket_id in PCL_VARS.WAITLIST_FOR_UNIXSOCKET_DICT) {
            PCL_VARS.WAITLIST_FOR_UNIXSOCKET_DICT[to_unixsocket_id].push(msg);
        } else {
            PCL_VARS.WAITLIST_FOR_UNIXSOCKET_DICT[to_unixsocket_id] = [msg];
        }
    }
}
/**  -------------------------------------------- PEER TO PEER --------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ REGISTER/UNREGISTER SOCKETS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */


// Register the unixsocket id.
function register_unixsocket(iosocket, unixsocket_id) {
    if (unixsocket_id in PCL_VARS.UNIXSOCKET_TO_IOSOCKET_DICT) {
        const error_msg = 'The socket with id ' + unixsocket_id + ' already registered!';
        console.log(error_msg);

        send_msg_to_peer(iosocket, {
            'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
            'operation': PCL_CONSTS.REGISTER_UNIXSOCKET_OP,
            'result': PCL_CONSTS.FAIL_STATUS,
            'unixsocket_id': unixsocket_id,
            'error_msg': error_msg
        });
        return;
    }

    // Update the first map.
    PCL_VARS.UNIXSOCKET_TO_IOSOCKET_DICT[unixsocket_id] = iosocket;

    // Update the second map.
    if (iosocket.id in PCL_VARS.IOSOCKET_TO_UNIXSOCKETS_DICT) {
        PCL_VARS.IOSOCKET_TO_UNIXSOCKETS_DICT[iosocket.id].push(unixsocket_id);
    } else {
        PCL_VARS.IOSOCKET_TO_UNIXSOCKETS_DICT[iosocket.id] = [unixsocket_id];
    }

    send_msg_to_peer(iosocket, {
        'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
        'operation': PCL_CONSTS.REGISTER_UNIXSOCKET_OP,
        'result': PCL_CONSTS.OK_STATUS,
        'unixsocket_id': unixsocket_id
    });

    if (unixsocket_id in PCL_VARS.WAITLIST_FOR_UNIXSOCKET_DICT) {
        var queue = PCL_VARS.WAITLIST_FOR_UNIXSOCKET_DICT[unixsocket_id];
        var len = queue.length;

        for (var i = 0; i < len; i++) {
            send_msg_to_peer(iosocket, queue[i]);
        }

        delete PCL_VARS.WAITLIST_FOR_UNIXSOCKET_DICT[unixsocket_id]; // empty the waitlist
    }
}

// Unregister the unixsocket id.
function unregister_unixsocket(iosocket, unixsocket_id) {

    // Remove the unixsocket from both maps, if it's there.
    if (unixsocket_id in PCL_VARS.UNIXSOCKET_TO_IOSOCKET_DICT) {
        delete PCL_VARS.UNIXSOCKET_TO_IOSOCKET_DICT[unixsocket_id];

        if (iosocket.id in PCL_VARS.IOSOCKET_TO_UNIXSOCKETS_DICT) {
            var index_of_unix = PCL_VARS.IOSOCKET_TO_UNIXSOCKETS_DICT[iosocket.id].indexOf(unixsocket_id);
            if (index_of_unix > -1)
                PCL_VARS.IOSOCKET_TO_UNIXSOCKETS_DICT[iosocket.id].splice(index_of_unix, 1);
        }

        send_msg_to_peer(iosocket, {
            'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
            'operation': PCL_CONSTS.UNREGISTER_UNIXSOCKET_OP,
            'result': PCL_CONSTS.OK_STATUS,
            'unixsocket_id': unixsocket_id
        });
    } else {
        // Otherwise, an error.
        var error_msg = 'Error - unregister_unixsocket: unixsocket ' + unixsocket_id + ' not registered with server!';
        console.log(error_msg);

        send_msg_to_peer(iosocket, {
            'kind': PCL_CONSTS.SERVER_TO_PEER_KIND,
            'operation': PCL_CONSTS.UNREGISTER_UNIXSOCKET_OP,
            'result': PCL_CONSTS.FAIL_STATUS,
            'unixsocket_id': unixsocket_id,
            'error_msg': error_msg
        });
    }
}
