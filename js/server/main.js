var app = require('http').createServer(handler);
var io = require('socket.io')(app);

app.listen(3000);

function handler(req, res) {
  res.writeHead(200);
  res.end("<!doctype html><html><head><title>ss</title></head><body></body></html>");
}

console.log('Listening on port:', 3000);


// When a new socket is created, register its possible handshakes.
io.on('connection', function (iosocket) {
    iosocket.on('register_zmqsocket', function (data) {
        register_zmqsocket(iosocket, data);
    });
    iosocket.on('unregister_zmqsocket', function (data) {
        unregister_zmqsocket(socket, data);
    });
    iosocket.on('contact_zmqsocket', function (data) {
        contact_zmqsocket(socket, data);
    });

    iosocket.emit('connected_to_server', 'ok');
});


var zmqsocket_to_iosocket = {};
var iosocket_to_zmqsockets = {};

// Requests to contact a zmqsocket that are yet to be satisfied.
var waitlist_for_zmqsocket = {};

// Register the zmqsocket id.
function register_zmqsocket(iosocket, data) {
    var zmqsocket_id = data.zmqsocket_id;

    // Update the first map.
    zmqsocket_to_iosocket[zmqsocket_id] = iosocket;

    // Update the second map.
    if (iosocket.id in iosocket_to_zmqsockets)
        iosocket_to_zmqsockets[iosocket.id].push(zmqsocket_id);
    else
        iosocket_to_zmqsockets[iosocket.id] = [zmqsocket_id];

    if (zmqsocket_id in waitlist_for_zmqsocket) {
        var queue = waitlist_for_zmqsocket[zmqsocket_id];
        var len = queue.length;
        waitlist_for_zmqsocket[zmqsocket_id] = [];

        for (var i = 0; i < len; i++) {
            var from_iosocket = queue[i].from_iosocket;
            var data = queue[i].data;
            send_message_to_zmqsocket(from_iosocket, zmqsocket_id, data);
        }
    }
}

// Unregister the zmqsocket id.
function unregister_zmqsocket(iosocket, data) {
    var zmqsocket_id = data.zmqsocket_id;

    // Remove the zmqsocket from both maps, if it's there.
    if (zmqsocket_id in zmqsocket_to_iosocket) {
        delete zmqsocket_to_iosocket[zmqsocket_id];

        if (iosocket.id in iosocket_to_zmqsockets) {
            var index_of_zmq = iosocket_to_zmqsockets[iosocket.id].indexOf(zmqsocket_id);
            if (index_of_zmq > -1)
                iosocket_to_zmqsockets[iosocket.id].splice(index_of_zmq, 1);
        }
    } else {
        // Otherwise, an error.
        var error_msg = 'Error - unregister_zmqsocket: Zmqsocket ' + zmqsocket_id + ' not registered with server.';
        iosocket.emit('fail_unregister_zmqsocket', {error_msg: error_msg, zmqsocket_id: zmqsocket_id});
        console.log(error_msg);
    }
}

// When the zmqsocket is present.
function send_message_to_zmqsocket(from_iosocket, to_zmqsocket_id, data) {
    var to_iosocket = zmqsocket_to_iosocket[to_zmqsocket_id];

    to_iosocket.emit('from_zmqsocket', data);
    from_iosocket.emit('ok_contact_zmqsocket', {to_zmqsocket_id: to_zmqsocket_id, msg_id: data.msg_id});
}

// Send a message to another zmqsocket.
function contact_zmqsocket(iosocket, data) {
    var to_zmqsocket_id = data.to_zmqsocket_id;

    if (to_zmqsocket_id in zmqsocket_to_iosocket) {
        send_message_to_zmqsocket(iosocket, to_zmqsocket_id, data);
    } else {
        var error_msg = 'Error - contact_zmqsocket: Zmqsocket ' + to_zmqsocket_id + ' not registered with server.';
        iosocket.emit('fail_contact_zmqsocket', {error_msg: error_msg, to_zmqsocket_id: to_zmqsocket_id});
        console.log(error_msg);

        if ('discard_on_fail' in data) {
            // Simply discard this message if no such zmqsocket exists.
        } else {
            // otherwise, send it when the zmqsocket registers.
            if (to_zmqsocket_id in waitlist_for_zmqsocket)
                waitlist_for_zmqsocket[to_zmqsocket_id].push({data: data, from_iosocket: iosocket});
            else
                waitlist_for_zmqsocket[to_zmqsocket_id] = [{data: data, from_iosocket: iosocket}];
        }
    }
}