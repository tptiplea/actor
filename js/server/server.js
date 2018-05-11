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
       'kind': 'SERVER_TO_PEER',
       'operation': 'CONNECTION',
       'result': 'SUCCESS'
    });
});


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ COMMUNICATE ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
function send_msg_to_peer(iosocket, msg) {
    iosocket.emit('server_to_peer', msg);
}

function process_msg_from_peer(iosocket, msg) {
    const kind = msg['kind'];

    if (kind === 'PEER_TO_SERVER') {
        // This is a message from the peer, for the server.
        const operation = msg['operation'];

        if (operation === 'REGISTER_UNIXSOCKET') {
            register_unixsocket(iosocket, msg['unixsocket_id']);
        } else if (operation === 'UNREGISTER_UNIXSOCKET') {
            unregister_unixsocket(iosocket, msg['unixsocket_id']);
        }

    } else if (kind === 'PEER_TO_PEER') {
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
    const to_unixsocket_id = msg['to_unixsocket_id'];

    if (to_unixsocket_id in unixsocket_to_iosocket) {
        const to_iosocket = unixsocket_to_iosocket[to_unixsocket_id];
        send_msg_to_peer(to_iosocket, msg);

        send_msg_to_peer(to_iosocket, {
            'kind': 'FROM_SERVER',
            'operation': 'PEER_TO_PEER_OP',
            'result': 'SUCCESS',
            'msg_id': msg['msg_id']
        });
    } else {
        const error_msg = 'Error - P2P: unixsocket ' + to_unixsocket_id + ' not registered with server!';
        console.log(error_msg);

        send_msg_to_peer(to_iosocket, {
            'kind': 'FROM_SERVER',
            'operation': 'PEER_TO_PEER_OP',
            'result': 'FAIL',
            'msg_id': msg['msg_id'],
            'error_msg': error_msg
        });

        if (to_unixsocket_id in waitlist_for_unixsocket)
            waitlist_for_unixsocket[to_unixsocket_id].push({data: data, from_iosocket: iosocket});
        else
            waitlist_for_unixsocket[to_unixsocket_id] = [{data: data, from_iosocket: iosocket}];
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
            'kind': 'SERVER_TO_PEER',
            'operation': 'REGISTER_UNIXSOCKET',
            'result': 'FAIL',
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
        'kind': 'SERVER_TO_PEER',
        'operation': 'REGISTER_UNIXSOCKET',
        'result': 'SUCCESS',
        'unixsocket_id': unixsocket_id
    });

    if (unixsocket_id in waitlist_for_unixsocket) {
        let queue = waitlist_for_unixsocket[unixsocket_id];
        let len = queue.length;

        for (let i = 0; i < len; i++) {
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
            let index_of_unix = iosocket_to_unixsockets[iosocket.id].indexOf(unixsocket_id);
            if (index_of_unix > -1)
                iosocket_to_unixsockets[iosocket.id].splice(index_of_unix, 1);
        }

        send_msg_to_peer(iosocket, {
            'kind': 'SERVER_TO_PEER',
            'operation': 'UNREGISTER_UNIXSOCKET',
            'result': 'SUCCESS',
            'unixsocket_id': unixsocket_id
        });
    } else {
        // Otherwise, an error.
        let error_msg = 'Error - unregister_unixsocket: unixsocket ' + unixsocket_id + ' not registered with server!';
        console.log(error_msg);

        send_msg_to_peer(iosocket, {
            'kind': 'SERVER_TO_PEER',
            'operation': 'UNREGISTER_UNIXSOCKET',
            'result': 'FAIL',
            'unixsocket_id': unixsocket_id,
            'error_msg': error_msg
        });
    }
}
