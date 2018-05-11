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
    iosocket.on('register_unixsocket', function (data) {
        register_unixsocket(iosocket, data);
    });
    iosocket.on('unregister_unixsocket', function (data) {
        unregister_unixsocket(socket, data);
    });
    iosocket.on('contact_unixsocket', function (data) {
        contact_unixsocket(socket, data);
    });

    iosocket.emit('connected_to_server', 'ok');
});


var unixsocket_to_iosocket = {};
var iosocket_to_unixsockets = {};

// Requests to contact a unixsocket that are yet to be satisfied.
var waitlist_for_unixsocket = {};

// Register the unixsocket id.
function register_unixsocket(iosocket, data) {
    var unixsocket_id = data.unixsocket_id;

    if (unixsocket_id in unixsocket_to_iosocket) {
        iosocket.emit('fail_register_unixsocket', {error_msg: 'The socket with id ' + unixsocket_id + ' already registered '});
        return;
    }

    // Update the first map.
    unixsocket_to_iosocket[unixsocket_id] = iosocket;

    // Update the second map.
    if (iosocket.id in iosocket_to_unixsockets)
        iosocket_to_unixsockets[iosocket.id].push(unixsocket_id);
    else
        iosocket_to_unixsockets[iosocket.id] = [unixsocket_id];

    if (unixsocket_id in waitlist_for_unixsocket) {
        var queue = waitlist_for_unixsocket[unixsocket_id];
        var len = queue.length;
        waitlist_for_unixsocket[unixsocket_id] = [];

        for (var i = 0; i < len; i++) {
            var from_iosocket = queue[i].from_iosocket;
            var data = queue[i].data;
            send_message_to_unixsocket(from_iosocket, unixsocket_id, data);
        }
    }

    iosocket.emit('ok_register_unixsocket', {'unixsocket_id': unixsocket_id});
}

// Unregister the unixsocket id.
function unregister_unixsocket(iosocket, data) {
    var unixsocket_id = data.unixsocket_id;

    // Remove the unixsocket from both maps, if it's there.
    if (unixsocket_id in unixsocket_to_iosocket) {
        delete unixsocket_to_iosocket[unixsocket_id];

        if (iosocket.id in iosocket_to_unixsockets) {
            var index_of_unix = iosocket_to_unixsockets[iosocket.id].indexOf(unixsocket_id);
            if (index_of_unix > -1)
                iosocket_to_unixsockets[iosocket.id].splice(index_of_unix, 1);
        }
    } else {
        // Otherwise, an error.
        var error_msg = 'Error - unregister_unixsocket: unixsocket ' + unixsocket_id + ' not registered with server.';
        iosocket.emit('fail_unregister_unixsocket', {error_msg: error_msg, unixsocket_id: unixsocket_id});
        console.log(error_msg);
    }
}

// When the unixsocket is present.
function send_message_to_unixsocket(from_iosocket, to_unixsocket_id, data) {
    var to_iosocket = unixsocket_to_iosocket[to_unixsocket_id];

    to_iosocket.emit('from_unixsocket', data);
    from_iosocket.emit('ok_contact_unixsocket', {to_unixsocket_id: to_unixsocket_id, msg_id: data.msg_id});
}

// Send a message to another unixsocket.
function contact_unixsocket(iosocket, data) {
    var to_unixsocket_id = data.to_unixsocket_id;

    if (to_unixsocket_id in unixsocket_to_iosocket) {
        send_message_to_unixsocket(iosocket, to_unixsocket_id, data);
    } else {
        var error_msg = 'Error - contact_unixsocket: unixsocket ' + to_unixsocket_id + ' not registered with server.';
        iosocket.emit('fail_contact_unixsocket', {error_msg: error_msg, to_unixsocket_id: to_unixsocket_id});
        console.log(error_msg);

        if (('server_discard_on_fail' in data) && (data['server_discard_on_fail'] === true)) {
            // otherwise, send it when the unixsocket registers.
            if (to_unixsocket_id in waitlist_for_unixsocket)
                waitlist_for_unixsocket[to_unixsocket_id].push({data: data, from_iosocket: iosocket});
            else
                waitlist_for_unixsocket[to_unixsocket_id] = [{data: data, from_iosocket: iosocket}];
        } else {
            // Simply discard this message if no such unixsocket exists.
        }
    }
}