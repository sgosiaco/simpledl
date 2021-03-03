import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ext_storage/ext_storage.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:safe_filename/safe_filename.dart' as SafeFilename;

import 'package:simpledl/VideoDetails.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SimpleDL());
}

class SimpleDL extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimpleDL',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription _intentData;
  final _yt = YoutubeExplode();
  final _ffmpeg = FlutterFFmpeg();
  final _ffmpegConfig = FlutterFFmpegConfig();
  TextEditingController _urlController;
  Video _video;
  String _operation = 'Nothing...';
  String _ffmpegLog = '';
  double _progress = 0;
  int _count = 0;
  int _len = 0;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();

    _intentData = ReceiveSharingIntent.getTextStream().listen((value) async {
      await loadVideo(value);
    }, onError: (err) {
      print('Error $err');
    });

    ReceiveSharingIntent.getInitialText().then((value) async {
      await loadVideo(value);
    });

    _ffmpegConfig.enableLogCallback((log) {
      setState(() {
        _ffmpegLog = log.message;
      });
      devlog(log.message);
    });
  }

  @override
  void dispose() {
    _intentData.cancel();
    _urlController.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _urlController,
            style: TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Youtube URL',
              hintStyle: TextStyle(color: Colors.white)
            ),
            onSubmitted: (value) async {
              await loadVideo(value);
            },
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              VideoDetails(
                video: _video,
                download: download,
                cancel: () {
                  _ffmpeg.cancel();
                  resetState(false);
                },
              ),
              Status(progress: _progress, operation: _operation, log: _ffmpegLog)
            ],
          ),
        ),
      ),
    );
  }

  void resetState(bool error) {
    setState(() {
      _video = null;
      _progress = 0;
      _operation = 'Nothing...';
      if (!error) {
        _ffmpegLog = '';
      }
      _count = 0;
      _len = 0;
    });
  }

  Future<void> loadVideo(String url) async {
    if (url != null) {
      final video = await _yt.videos.get(url);
      setState(() {
        _urlController.text = url;
        _video = video;
      });
    }
  }

  List<int> updateProgress(List<int> chunk) {
    _count += chunk.length;
    setState(() {
      _progress = _count / _len;
    });
    return chunk;    
  }

  Future<void> download() async {
    if (_operation != 'Nothing...') {
      return;
    }
    if (await Permission.storage.request().isDenied) {
      return;
    }
    // Download manifest
    setState(() {
      _operation = 'Downloading manifest...';
    });
    final manifest = await _yt.videos.streamsClient.getManifest(_video.id);
    final audioInfo = manifest.audio.withHighestBitrate(); //manifest.audioOnly.withHighestBitrate();
    final musicDir = await ExtStorage.getExternalStoragePublicDirectory(ExtStorage.DIRECTORY_MUSIC);
    final dlDir = p.join(musicDir, 'simpledl');
    if (!(await Directory(dlDir).exists())) {
      await Directory(dlDir).create();
      print('Created directory');
    }
    if (audioInfo != null) {
      final path = p.join(dlDir, 'temp1.${audioInfo.container.name}');
      final temp = p.join(dlDir, 'temp2.mp3');
      final output = p.join(dlDir, '${SafeFilename.encode(_video.title)}.mp3');
      final stream = _yt.videos.streamsClient.get(audioInfo);

      // Download audio and update progress bar
      setState(() {
        _operation = 'Downloading audio...';
      });
      _len = audioInfo.size.totalBytes;
      _count = 0;

      await stream.map(updateProgress).pipe(File(path).openWrite());


      // Download thumbnail for album art
      setState(() {
        _progress = 0;
        _operation = 'Downloading thumbnail...';
      });

      final response = await http.Client().send(http.Request('GET', Uri.parse(_video.thumbnails.highResUrl)));
      final art = p.join(dlDir, 'temp.png');
      
      _len = response.contentLength;
      _count = 0;

      await response.stream.map(updateProgress).pipe(File(art).openWrite());

      // Convert downloaded media into mp3 with tags
      setState(() {
        _progress = 0;
        _operation = 'Converting audio...';
        _progress = null;
      });
      var ret = await _ffmpeg.execute('-i $path -metadata title="${_video.title}" -metadata artist="${_video.author}" -metadata author_url="${_video.url}" $temp');
      await File(path).delete();

      if (ret != 0) {
        print('Transcode Error!');
        await File(temp).delete();
        await File(art).delete();
        _ffmpegLog = 'Transcode Error! Please retry!';
        resetState(true);
        return;
      }

      // Add album art to mp3
      setState(() {
        _progress = 0;
        _operation = 'Adding album art...';
        _progress = null;
      });
      ret = await _ffmpeg.execute('-i $temp -i $art -map 0:0 -map 1:0 -c copy -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (Front)" $output');

      await File(temp).delete();
      await File(art).delete();

      if (ret != 0) {
        print('Album Art Error!');
        await File(output).delete();
        _ffmpegLog = 'Album Art Error! Please retry!';
        resetState(true);
        return;
      }

      resetState(false);
    }
  }
}


class Status extends StatelessWidget {
  final double progress;
  final String operation;
  final String log;
  Status({@required this.progress, @required this.operation, @required this.log});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          backgroundColor: Colors.blue[200],
          valueColor: AlwaysStoppedAnimation(Colors.blue[800]),
          value: progress
        ),
        ListTile(
          title: Text(operation),
          subtitle: Text(log),
        )
      ],
    );
  }
}

void devlog(String message, {String name = '', Object error}) {
  if (kDebugMode) {
    dev.log(message, name: 'io.github.sgosiaco.simpledl$name', error: error);
  }
}