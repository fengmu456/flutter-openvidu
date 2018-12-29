import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:http/http.dart';
import 'package:openvidu_demo/test.dart';



void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenVidu',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'OpenVidu'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // 表单数据
  Map<String, String> formData = Map();

  // 输入框
  Widget _inputBox(String name, String label, String defaultVal) {
    if (!formData.containsKey(name)) {
      formData[name] = defaultVal;
    }
    var controller = TextEditingController.fromValue(
      TextEditingValue(text: formData[name]),
    );
    return TextField(
      key: Key("input$name"),
      decoration: InputDecoration(
        hasFloatingPlaceholder: true,
        labelText: label,
      ),
      textAlign: TextAlign.center,
      controller: controller,
      onChanged: (val) => formData[name] = val,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: EdgeInsets.only(left: 20, right: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _inputBox("roomName", "Room Name:", "test"),
            _inputBox("userName", "User Name:", "FlutterUser"),
            _inputBox("server", "Server:", "demos.openvidu.io"),
            _inputBox("secret", "Secret:", "MY_SECRET"),
            Container(
              width: 200,
              margin: EdgeInsets.only(top: 50),
              child: FlatButton(
                child: Text("Join"),
                color: Colors.blue,
                textColor: Colors.white,
                padding: EdgeInsets.all(15),
                onPressed: _join,
              ),
            )
          ],
        ),
      ),
    );
  }

  void _join() {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return TestRoom(
        roomName: formData["roomName"],
        userName: formData["userName"],
        server: formData["server"],
        secret: formData["secret"],
      );
    }));
  }
}
