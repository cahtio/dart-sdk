import 'package:tinode/src/models/topic-description.dart';

class OfficialAccountSetParams {
  TopicDescription? desc;
  List<String>? tags;

  OfficialAccountSetParams({this.desc, this.tags});
}

class OfficialAccountParams {
  OfficialAccountSetParams? setParams;

  OfficialAccountParams({this.setParams});
}

