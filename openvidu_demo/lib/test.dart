import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:http/http.dart';
import 'package:flutter_openvidu/flutter_openvidu.dart';

class TestRoom extends StatefulWidget {
  const TestRoom({
    Key key,
    this.userName,
    this.roomName,
    this.server,
    this.secret,
  }) : super(key: key);

  final String userName;
  final String roomName;
  final String server;
  final String secret;

  @override
  _TestRoomState createState() => _TestRoomState();
}

class _TestRoomState extends State<TestRoom> {
  OpenVidu openVidu;
  Map<String, VideoView> views = Map();

  @override
  initState() {
    super.initState();
    openVidu = new OpenVidu(
      wssClientServer: "wss://${widget.server}:4443/openvidu",
      turnServer: "${widget.server}:3478",
      connectionChangeCallback: (OpenViduConnection conn, type) async {
        if (type == CONNECTION_CHANGE_TYPE.CREATE) {
          VideoRenderer renderer = VideoRenderer();
          await renderer.initialize();
          renderer.srcObject = conn.stream;
          VideoView view = VideoView(renderer, 0.56);
          views[conn.sortId] = view;
        } else if (type == CONNECTION_CHANGE_TYPE.DESTROY) {
          var view = views[conn.sortId];
          view.renderer.dispose();
          views.remove(conn.sortId);
        }
        setState(() => null);
      },
    );
    _join();
  }

  Future<String> _getToken() async {
    var auth = base64.encode("OPENVIDUAPP:${widget.secret}".codeUnits);
    var data = await post(
      "https://${widget.server}:4443/api/tokens",
      headers: {
        "Authorization": "Basic ${auth}",
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "session": widget.roomName,
        "role": "PUBLISHER",
        "data:": {"clientData": widget.userName}.toString()
      }),
    );
    var json = jsonDecode(data.body);
    return json["token"];
  }

  void _join() async {
    openVidu.join(widget.roomName, await _getToken(), {
      "clientData": widget.userName,
    });
  }

  void dispose() {
    super.dispose();
    openVidu.exit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("OpenViduDemo"),
      ),
      body: ListView(
        children: views.values.toList(),
      ),
    );
  }
}
