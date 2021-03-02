import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ext_storage/ext_storage.dart';
import 'package:path/path.dart' as p;
import 'package:audiotagger/audiotagger.dart';

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
  final yt = YoutubeExplode();
  final tagger = Audiotagger();
  TextEditingController _urlController;
  Video _video;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
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
                  final path = p.join(dlDir, '${_video.title}.mp3');
                  if (audioInfo != null) {
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
                    final response = await http.get(_video.thumbnails.highResUrl);
                    await tagger.writeTagsFromMap(
                      path: path, 
                      tags: {
                        'title': _video.title,
                        'artist': _video.author,
                        'artwork': response.bodyBytes
                      }
                    );
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