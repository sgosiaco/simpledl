import 'dart:async';
import 'dart:io';
//import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ext_storage/ext_storage.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:safe_filename/safe_filename.dart' as SafeFilename;

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
  StreamSubscription _intentDataStreamSubscription;
  final yt = YoutubeExplode();
  final ffmpeg = FlutterFFmpeg();
  TextEditingController _urlController;
  Video _video;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();

    _intentDataStreamSubscription = ReceiveSharingIntent.getTextStream().listen((value) async {
      if (value != null) {
        final video =  await yt.videos.get(value);
        setState(() {
          _urlController.text = value;
          _video = video;
        });
      }
    }, onError: (err) {
      print('Error $err');
    });

    ReceiveSharingIntent.getInitialText().then((value) async {
      if (value != null) {
        final video =  await yt.videos.get(value);
        setState(() {
          _urlController.text = value;
          _video = video;
        });
      }
    });

  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    _urlController.dispose();
    yt.close();
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
              final video =  await yt.videos.get(value);
              setState(() {
                _video = video;
              });
            },
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              VideoDetails(
                video: _video,
                download: () async {
                  if (await Permission.storage.request().isDenied) {
                    return;
                  }
                  final manifest = await yt.videos.streamsClient.getManifest(_video.id);
                  final audioInfo = manifest.audioOnly.withHighestBitrate();
                  //final videoInfo = manifest.audio.withHighestBitrate();
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
                    final stream = yt.videos.streamsClient.get(audioInfo);
                    
                    final file = File(path);
                    final fileStream = file.openWrite();

                    final len = audioInfo.size.totalBytes;
                    var count = 0;

                    await for (var data in stream) {
                      count += data.length;
                      setState(() {
                        _progress = count / len;
                      });
                      fileStream.add(data);
                    }
                    
                    //await stream.pipe(fileStream);
                    //await fileStream.flush();
                    await fileStream.close();
                    final request = await HttpClient().getUrl(Uri.parse(_video.thumbnails.highResUrl));
                    final resposne = await request.close();
                    final art = p.join(dlDir, 'temp.png');
                    resposne.pipe(File(art).openWrite());
                    //final response = await http.get(_video.thumbnails.highResUrl);
                    

                    var ret = await ffmpeg.execute('-i $path -metadata title="${_video.title}" -metadata artist="${_video.author}" -metadata author_url="${_video.url}" $temp');

                    await File(path).delete();

                    if (ret != 0) {
                      print('Transcode Error!');
                      setState(() {
                        _video = null;
                        _progress = 0;
                      });
                      return;
                    }

                    ret = await ffmpeg.execute('-i $temp -i $art -map 0:0 -map 1:0 -c copy -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (Front)" $output');

                    await File(temp).delete();
                    await File(art).delete();

                    if (ret != 0) {
                      print('Album Art Error!');
                      setState(() {
                        _video = null;
                        _progress = 0;
                      });
                      return;
                    }


                    setState(() {
                      _video = null;
                      _progress = 0;
                    });
                  }
                },
                clearVideo: () {
                  setState(() {
                    _video = null;
                    _progress = 0;
                  });
                },
              ),
              LinearProgressIndicator(
                backgroundColor: Colors.blue[200],
                valueColor: AlwaysStoppedAnimation(Colors.blue[800]),
                value: _progress
              )
            ],
          ),
        ),
      ),
    );
  }
}


class VideoDetails extends StatelessWidget {
  final Video video;
  final Function download;
  final Function clearVideo;
  VideoDetails({@required this.video, @required this.download, @required this.clearVideo});  

  @override
  Widget build(BuildContext context) {
    if (video == null) {
      return Column(
        children: [
          Text('Please enter a link in the field above')
        ]
      );
    }
    return Card(
      color: Colors.blue,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: Text(video.title, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white),),
            subtitle: Text(video.author, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white),),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Image.network(video.thumbnails.maxResUrl)
          ),
          ButtonBar(
            alignment: MainAxisAlignment.end,
            children: [
              FlatButton(
                child: Text('Download', style: TextStyle(color: Colors.white),),
                onPressed: () {
                  download();
                },
              ),
              FlatButton(
                child: Text('Cancel', style: TextStyle(color: Colors.white),),
                onPressed: () {
                  clearVideo();
                },
              )
            ],
          )
        ],
      )
    );
  }
}