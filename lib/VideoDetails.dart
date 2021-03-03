import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoDetails extends StatelessWidget {
  final Video video;
  final Function download;
  final Function clearVideo;
  VideoDetails({@required this.video, @required this.download, @required this.clearVideo});

  @override
  Widget build(BuildContext context) {
    if (video == null) {
      return Column(children: [Text('Please enter a link in the field above')]);
    }
    return Card(
      color: Colors.blue,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: Text(
              video.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              video.author,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Image.network(video.thumbnails.maxResUrl)
          ),
          ButtonBar(
            alignment: MainAxisAlignment.end,
            children: [
              FlatButton(
                child: Text(
                  'Download',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () {
                  download();
                },
              ),
              FlatButton(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white),
                ),
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
