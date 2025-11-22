import 'package:get_it/get_it.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tinode/src/models/moment.dart';
import 'dart:math';

import 'package:tinode/src/models/topic-names.dart' as topic_names;
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/topic-description.dart';
import 'package:tinode/src/models/server-messages.dart';
import 'package:tinode/src/services/auth.dart';
import 'package:tinode/src/services/cache-manager.dart';
import 'package:tinode/src/models/contact-update.dart';
import 'package:tinode/src/models/access-mode.dart';
import 'package:tinode/src/models/credential.dart';
import 'package:tinode/src/services/database-manager.dart';
import 'package:tinode/src/services/logger.dart';
import 'package:tinode/src/services/tinode.dart';
import 'package:tinode/src/services/tools.dart';
import 'package:tinode/src/models/message.dart';
import 'package:tinode/src/models/values.dart';
import 'package:tinode/src/topic.dart';

/// Special case of Topic for managing data of the current user, including contact list
class TopicMe extends Topic {
  /// List of contacts (topic_name -> Contact object)
  final Map<String, TopicSubscription> _contacts = {};

  /// This event will be triggered when a contact is updated
  PublishSubject<ContactUpdateEvent> onContactUpdate =
      PublishSubject<ContactUpdateEvent>();

  /// This event will be triggered when credentials are updated
  PublishSubject<List<Credential>> onCredsUpdated =
      PublishSubject<List<Credential>>();

  PublishSubject<List<Moment>> onMomentsUpdated =
      PublishSubject<List<Moment>>();
  List<Moment> _moments = <Moment>[];
  // static const momentsKey = 'moments';

  PublishSubject<List<MomentNotification>> onNotificationUpdated =
      PublishSubject<List<MomentNotification>>();
  List<MomentNotification> _notifications = <MomentNotification>[];
  // static const momentsKey = 'notification';

  /// This event will be triggered when comments are updated
  PublishSubject<List<MomentComment>> onCommentsUpdated =
      PublishSubject<List<MomentComment>>();
  Map<int, List<MomentComment>> _commentsMap = {};

  // Credentials such as email or phone number.
  List<Credential> _credentials = [];

  /// Tinode service, responsible for handling messages, preparing packets and sending them
  late TinodeService _tinodeService;

  /// Cache manager service, responsible for read and write operations on cached data
  late CacheManager _cacheManager;

  /// Logger service, responsible for logging content in different levels
  late LoggerService _loggerService;

  late DatabaseManager _databaseManager;

  late AuthService _authService;

  TopicMe() : super(topic_names.TOPIC_ME) {
    _cacheManager = GetIt.I.get<CacheManager>();
    _tinodeService = GetIt.I.get<TinodeService>();
    _loggerService = GetIt.I.get<LoggerService>();
    _authService = GetIt.I.get<AuthService>();
    _databaseManager = GetIt.I.get<DatabaseManager>();
  }

  /// Override the original Topic.processMetaDesc.
  @override
  void processMetaDesc(TopicDescription desc) {
    // Check if online contacts need to be turned off because P permission was removed.
    var turnOff = (desc.acs != null && !desc.acs!.isPresencer(null)) &&
        acs.isPresencer(null);

    // Copy parameters from desc object to this topic
    acs = desc.acs ?? acs;
    clear = desc.clear ?? clear;
    created = desc.created ?? created;
    defacs = desc.defacs ?? defacs;
    private = desc.private ?? private;
    public = desc.public ?? public;
    read = desc.read ?? read;
    recv = desc.recv ?? recv;
    seq = desc.seq ?? seq;
    status = desc.status ?? status;
    updated = desc.updated ?? updated;
    touched = desc.touched ?? touched;

    _updateCached(desc);

    if (turnOff) {
      _contacts.forEach((key, cont) {
        if (cont.online == true) {
          cont.online = false;
          if (cont.seen != null) {
            cont.seen!.when = DateTime.now();
          } else {
            cont.seen = Seen(when: DateTime.now());
          }
          onContactUpdate.add(ContactUpdateEvent('off', cont));
        }
      });
    }

    onMetaDesc.add(this);
  }

  /// Override the original Topic.processMetaSub
  @override
  void processMetaSub(List<TopicSubscription> subscriptions) async {
    for (var sub in subscriptions) {
      var topicName = sub.topic;
      // Don't show 'me' and 'fnd' topics in the list of contacts.
      if (topicName == topic_names.TOPIC_FND ||
          topicName == topic_names.TOPIC_ME) {
        continue;
      }

      var cont = TopicSubscription();
      if (sub.deleted != null) {
        _contacts.remove(topicName);
        _cacheManager.delete('topic', topicName ?? '');
      } else {
        // Ensure the values are defined and are integers.
        if (sub.seq != null) {
          sub.seq = sub.seq ?? 0;
          sub.recv = sub.recv ?? 0;
          sub.read = sub.read ?? 0;
          sub.unread = (sub.seq ?? 0) - (sub.read ?? 0);
        }

        var cached = _contacts[topicName];
        if (cached != null) {
          cached.acs = sub.acs ?? cached.acs;
          cached.clear = sub.clear ?? cached.clear;
          cached.created = sub.created ?? cached.created;
          cached.deleted = cached.deleted ?? cached.deleted;
          cached.mode = sub.mode ?? cached.mode;
          cached.noForwarding = sub.noForwarding ?? cached.noForwarding;
          cached.online = sub.online ?? cached.online;
          cached.private = sub.private ?? cached.private;
          cached.public = sub.public ?? cached.public;
          cached.read = sub.read ?? cached.read;
          cached.recv = sub.recv ?? cached.recv;
          cached.seen = sub.seen ?? cached.seen;
          cached.seen = sub.seen ?? cached.seen;
          cached.topic = sub.topic ?? cached.topic;
          // cached.touched = sub.touched ?? cached.touched;
          // cached.updated = sub.updated ?? cached.updated;
          cached.user = sub.user ?? cached.user;
          if ((sub.touched ?? DateTime.fromMicrosecondsSinceEpoch(0)).compareTo(
                  cached.touched ?? DateTime.fromMicrosecondsSinceEpoch(0)) >
              0) {
            cached.touched = sub.touched ?? cached.touched;
          }
          if ((sub.updated ?? DateTime.fromMicrosecondsSinceEpoch(0)).compareTo(
                  cached.updated ?? DateTime.fromMicrosecondsSinceEpoch(0)) >
              0) {
            cached.updated = sub.updated ?? cached.updated;
          }
        } else {
          cached = sub;
          _contacts[(topicName ?? '')] = sub;
        }
        cont = cached;

        if (topicName != null) {
          cont.lastMessage ??=
              await _databaseManager.message.lastMessage(topicName);
          if (Tools.isP2PTopicName(topicName)) {
            _cacheManager.putUser(topicName, cont);
          }
        }

        // Notify topic of the update if it's an external update.
        if (sub.noForwarding == false || sub.noForwarding == null) {
          var topic = _tinodeService.getTopic(topicName);
          if (topic != null) {
            sub.noForwarding = true;
            topic.processMetaDesc(sub.asDesc());
          }
        }
      }

      onMetaSub.add(cont);
    }

    onSubsUpdated.add(_contacts.values.toList());
  }

  /// Called by Tinode when meta.sub is received.
  @override
  void processMetaCreds(List<Credential> creds, bool update) {
    // ignore: unrelated_type_equality_checks
    if (creds.length == 1 && creds[0] == DEL_CHAR) {
      creds = [];
    }

    if (update) {
      creds.forEach((cr) {
        // Adding a credential.
        var idx = _credentials.indexWhere((el) {
          return el.meth == cr.meth && el.val == cr.val;
        });

        if (cr.val != null) {
          if (idx < 0) {
            // Not found.
            if (cr.done == false || cr.done == null) {
              // Unconfirmed credential replaces previous unconfirmed credential of the same method.
              idx = _credentials.indexWhere((el) {
                return el.meth == cr.meth &&
                    (el.done == false || cr.done == null);
              });
              if (idx >= 0) {
                // Remove previous unconfirmed credential.
                _credentials.removeAt(idx);
              }
            }
            _credentials.add(cr);
          } else {
            // Found. Maybe change 'done' status.
            _credentials[idx].done = cr.done;
          }
        } else if (cr.resp != null) {
          // Handle credential confirmation.
          idx = _credentials.indexWhere((el) {
            return el.meth == cr.meth && (el.done == false || cr.done == null);
          });

          if (idx >= 0) {
            _credentials[idx].done = true;
          }
        }
      });
    } else {
      _credentials = creds;
    }

    onCredsUpdated.add(_credentials);
  }

  /// Process presence change message
  @override
  void routePres(PresMessage pres) {
    if (pres.what == 'term') {
      // The 'me' topic itself is detached. Mark as unsubscribed.
      resetSubscription();
      return;
    }

    if (pres.what == 'upd' && pres.src == topic_names.TOPIC_ME) {
      // Update to me description. Request updated value.
      getMeta(startMetaQuery().withDesc(null).build());
      return;
    }

    var cont = _contacts[pres.src];
    if (cont != null) {
      switch (pres.what) {
        case 'on':
          // topic came online
          cont.online = true;
          break;
        case 'off':
          // topic went offline
          if (cont.online == true) {
            cont.online = false;
            if (cont.seen != null) {
              cont.seen?.when = DateTime.now();
            } else {
              cont.seen = Seen(when: DateTime.now());
            }
          }
          break;
        case 'msg':
          // new message received
          cont.touched = DateTime.now();
          cont.seq = (pres.seq ?? 0) | 0;
          // Check if message is sent by the current user. If so it's been read already.
          if (pres.act == null || _tinodeService.isMe(pres.act ?? '')) {
            cont.read = cont.read != null && cont.read != 0
                ? max((cont.read ?? 0), (cont.seq ?? 0))
                : cont.seq;
            cont.recv = cont.recv != null && cont.recv != 0
                ? max((cont.read ?? 0), (cont.recv ?? 0))
                : cont.read;
          }
          cont.unread = (cont.seq ?? 0) - ((cont.read ?? 0) | 0);
          break;
        case 'upd': // desc updated
          // Request updated subscription.
          getMeta(startMetaQuery().withLaterOneSub(pres.src).build());
          break;
        case 'acs':
          // access mode changed
          if (cont.acs != null) {
            cont.acs?.updateAll(pres.dacs);
          } else {
            cont.acs = AccessMode(null).updateAll(pres.dacs);
          }
          cont.touched = DateTime.now();
          break;
        case 'ua':
          // user agent changed
          cont.seen = Seen(when: DateTime.now(), ua: pres.ua);
          break;
        case 'recv': // user's other session marked some messages as received
          pres.seq = (pres.seq ?? 0) | 0;
          cont.recv = cont.recv != null && cont.recv != 0
              ? max((cont.recv ?? 0), (pres.seq ?? 0))
              : pres.seq;
          break;
        case 'read':
          // user's other session marked some messages as read
          pres.seq = (pres.seq ?? 0) | 0;
          cont.read = cont.read != null && cont.read != 0
              ? max((cont.read ?? 0), (pres.seq ?? 0))
              : pres.seq;
          cont.recv = cont.recv != null && cont.recv != 0
              ? max((cont.read ?? 0), (cont.recv ?? 0))
              : cont.recv;
          cont.unread = (cont.seq ?? 0) - (cont.read ?? 0);
          break;
        case 'gone':
          // topic deleted or unsubscribed from
          _contacts.remove(pres.src);
          _cacheManager.delete('topic', pres.src ?? '');
          break;
        case 'del':
          // Update topic.del value.
          break;
        default:
          _loggerService
              .log("Unsupported presence update in 'me' " + (pres.what ?? ''));
      }

      onContactUpdate.add(ContactUpdateEvent(pres.what!, cont));
    } else {
      if (pres.what == 'acs') {
        // New subscriptions and deleted/banned subscriptions have full
        // access mode (no + or - in the dacs string). Changes to known subscriptions are sent as
        // deltas, but they should not happen here.
        AccessMode? acs = AccessMode(pres.dacs);

        if (acs.mode == INVALID) {
          _loggerService.error('Invalid access mode update ' +
              (pres.src ?? '') +
              ' ' +
              pres.dacs.toString());
          return;
        } else if (acs.mode == NONE) {
          _loggerService.warn('Removing non-existent subscription ' +
              (pres.src ?? '') +
              ' ' +
              pres.dacs.toString());
        } else {
          // New subscription. Send request for the full description.
          // Using .withOneSub (not .withLaterOneSub) to make sure IfModifiedSince is not set.
          getMeta(startMetaQuery().withOneSub(null, pres.src).build());
          // Create a dummy entry to catch online status update.
          _contacts[pres.src ?? ''] = TopicSubscription(
              touched: DateTime.now(),
              topic: pres.src,
              online: false,
              acs: acs);
          // Immediately notify listeners with updated contacts snapshot so UI can reflect the new contact.
          onSubsUpdated.add(_contacts.values.toList());
        }
      } else if (pres.what == 'tags') {
        getMeta(startMetaQuery().withTags().build());
      }
    }

    onPres.add(pres);
  }

  void routeMoment(MomentMessage moment) {
    // print('routeMoment ${moment.moments.toList().map((e) => e.id)}');
    if (moment.moments.isNotEmpty && _moments.isNotEmpty) {
      if (moment.moments.first.id < _moments.last.id) {
        // print('routeMoment addAll ${moment.moments.first.id} < ${_moments.last.id}');
        _moments.addAll(moment.moments);
      } else if (moment.moments.last.id > _moments.first.id) {
        // print('routeMoment insertAll ${moment.moments.last.id} > ${_moments.first.id}');
        _moments.insertAll(0, moment.moments);
      } else {
        // 找到重复项 覆盖，不重复项插入
        for (int i = 0; i < moment.moments.length; i++) {
          int index = _moments
              .indexWhere((momentObj) => momentObj.id == moment.moments[i].id);
          var tempM = moment.moments[i];
          if (index != -1) {
            // 替换重复项
            _moments[index] = tempM;
          } else {
            if (tempM.id < _moments.last.id) {
              // print('routeMoment add one ${tempM.id} < ${_moments.last.id}');
              _moments.add(tempM);
            } else if (tempM.id > _moments.first.id) {
              // print('routeMoment insert one ${tempM.id} > ${_moments.first.id}');
              _moments.insert(0, tempM);
            }
          }
        }
      }
    } else if (moment.moments.isNotEmpty && _moments.isEmpty) {
      _moments = moment.moments;
    }

    // print('_routeMoment ${_moments.toList().map((e) => e.id)}');
    //  _moments = moment.moments;
    onMomentsUpdated.add(_moments);

    // if(_authService.userId != null) {
    //   print('_tinodeService.userId! ${_authService.userId!} ${_moments.toList()}');
    //   _cacheManager.put(momentsKey, _authService.userId!, _moments.toList());
    // }
  }

// 处理通知列表响应
  void routeNotification(NotificationMessage notification) {
    if (notification.notifications.isNotEmpty) {
      if (_notifications.isNotEmpty) {
        // 使用Set来跟踪已存在的通知ID，实现高效去重
        Set<int> existingIds = _notifications.map((n) => n.id).toSet();

        // 遍历新通知，只添加不存在的通知
        for (var newNotification in notification.notifications) {
          if (!existingIds.contains(newNotification.id)) {
            _notifications.add(newNotification);
          }
        }

        // 根据需要按时间排序（最新的在前）
        _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } else {
        // 如果现有通知列表为空，直接赋值并排序
        _notifications = List.from(notification.notifications);
        _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      // 通知监听器
      onNotificationUpdated.add(List.from(_notifications));
    }
  }

  /// 处理评论列表响应
  void routeComments(CommentMessage commentMessage) {
    print('routeComments ${commentMessage.comments.toList().map((e) => e.id)}');
    if (commentMessage.comments.isEmpty) {
      return;
    }

    // 获取第一个评论的 momentId，假设所有评论都属于同一个动态
    int momentId = commentMessage.comments.first.momentId;

    // 将评论存储到 map 中
    if (_commentsMap.containsKey(momentId)) {
      // 如果已经有该动态的评论，合并列表
      var existingComments = _commentsMap[momentId]!;
      var newComments = commentMessage.comments;

      // 简单合并，去重可以根据需求添加
      for (var comment in newComments) {
        if (!existingComments.any((c) => c.id == comment.id)) {
          existingComments.add(comment);
        }
      }
      existingComments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      // 如果是新的动态评论，直接添加
      _commentsMap[momentId] = List.from(commentMessage.comments);
    }

    // 触发更新事件
    onCommentsUpdated.add(_commentsMap[momentId]!);
  }

  @override
  Future<CtrlMessage> publishMessage(Message a) {
    return Future.error(Exception("Publishing to 'me' is not supported"));
  }

  Future publishMoment(SetMoment moment) {
    return _tinodeService.publishMoment(moment);
  }

  /// 发表评论
  /// [momId] 动态ID
  /// [content] 评论内容
  /// [topId] 顶级评论ID（可选，用于多级回复）
  /// [parentId] 父评论ID（可选，用于多级回复）
  /// [attachments] 附件列表（可选）
  Future<CtrlMessage> publishComment({
    required String topic,
    required int momId,
    required String content,
    int? topId,
    int? parentId,
    List<String>? attachments,
  }) async {
    final comment = SetComment(
      topic: topic,
      momId: momId,
      content: content,
      topId: topId,
      parentId: parentId,
      attachments: attachments,
    );

    final response = await _tinodeService.publishComment(comment);
    return response;
  }

  Future<CtrlMessage> touchGetNotifications({
    required String topic,
    int? since,
    int? before,
    int? limit,
  }) async {
    final response = await _tinodeService.touchGetNotifications(
      topic: topic,
      since: since,
      before: before,
      limit: limit,
    );
    return response;
  }

  // 获取朋友圈列表
  Future<CtrlMessage> touchGetMoments({
    required String topic,
    required String? channelTopic,
    String? user,
    int? since,
    int? before,
    int? limit,
  }) async {
    final response = await _tinodeService.touchGetMoments(
      topic: topic,
      channelTopic: channelTopic,
      user: user,
      since: since,
      before: before,
      limit: limit,
    );
    return response;
  }

  /// 获取评论列表
  /// [momId] 动态ID，必填
  /// [since] 从哪个ID开始查，可选
  /// [before] 从哪个ID之前查，可选
  /// [limit] 获取数量限制，可选
  Future<CtrlMessage> getComments({
    required int momId,
    int? since,
    int? before,
    int? limit,
  }) async {
    final response = await _tinodeService.getComments(
      topic: topic_names.TOPIC_ME,
      momId: momId,
      since: since,
      before: before,
      limit: limit,
    );
    return response;
  }

  /// 删除评论
  /// [momId] 动态ID
  /// [commentId] 评论ID
  Future<CtrlMessage> deleteComment({
    required int momId,
    required int commentId,
  }) async {
    final response = await _tinodeService.deleteComment(
      topic: topic_names.TOPIC_ME,
      momId: momId,
      commentId: commentId,
    );

    // 从本地缓存中删除该评论
    if (_commentsMap.containsKey(momId)) {
      _commentsMap[momId]?.removeWhere((comment) => comment.id == commentId);
      // 触发更新事件
      onCommentsUpdated.add(_commentsMap[momId] ?? []);
    }

    return response;
  }

  /// 点赞或取消点赞动态
  /// [momId] 动态ID
  /// [action] 操作类型：1表示点赞，0表示取消点赞
  Future<CtrlMessage> likeMoment({
    required int momId,
    required int action,
    required String topic,
  }) async {
    final response = await _tinodeService.likeMoment(
      topic: topic,
      momId: momId,
      action: action,
    );

    return response;
  }

  /// 删除朋友圈动态
  /// [momId] 动态ID
  Future<CtrlMessage> deleteMoment({
    required int momId,
  }) async {
    final response = await _tinodeService.deleteMoment(
      topic: topic_names.TOPIC_ME,
      momId: momId,
    );

    // 从本地缓存中删除该动态
    _moments.removeWhere((moment) => moment.id == momId);
    // 触发更新事件
    onMomentsUpdated.add(_moments);

    // 同时删除该动态的所有评论
    if (_commentsMap.containsKey(momId)) {
      _commentsMap.remove(momId);
    }

    return response;
  }

  /// Delete validation credential
  Future<CtrlMessage> deleteCredential(String method, String value) async {
    if (!isSubscribed) {
      return Future.error(
          Exception("Cannot delete credential in inactive 'me' topic"));
    }

    // Send {del} message, return promise
    var response = await _tinodeService.deleteCredential(method, value);
    var ctrl = CtrlMessage.fromMessage(response);

    // Remove deleted credential from the cache.
    var index = _credentials.indexWhere((el) {
      return el.meth == method && el.val == value;
    });

    if (index > -1) {
      _credentials.removeAt(index);
    }

    onCredsUpdated.add(_credentials);
    return ctrl;
  }

  List<TopicSubscription> get contacts {
    return _contacts.values.toList();
  }

  void setLastMessage(String contactName, DataMessage message, {bool del = false}) {
    final cont = _contacts[contactName];
    print('setLastMessage  ${message.seq} ${message.content}');
    if (cont == null) return;
    if ((cont.lastMessage?.seq ?? 0) <= (message.seq ?? 0)) {
      cont.updated = message.ts;
      cont.lastMessage = message;
      onContactUpdate.add(ContactUpdateEvent('last_msg', cont));
    } else if(del){
      // 删除最后一条消息 才会进这里
      cont.updated = DateTime.now();
      cont.lastMessage = message;
      onContactUpdate.add(ContactUpdateEvent('last_msg', cont));
    }
     
  }

  /// Update a cached contact with new read/received/message count
  void setMsgReadRecv(String contactName, String what, int seq, DateTime? ts) {
    var cont = _contacts[contactName];
    var oldVal, doUpdate = false;

    if (cont != null) {
      this.seq = seq;
      cont.seq = cont.seq ?? 0;
      cont.read = cont.read ?? 0;
      cont.recv = cont.recv ?? 0;
      switch (what) {
        case 'recv':
          oldVal = cont.recv;
          cont.recv = max(cont.recv ?? 0, seq);
          doUpdate = (oldVal != cont.recv);
          break;
        case 'read':
          oldVal = cont.read;
          cont.read = max(cont.read ?? 0, seq);
          doUpdate = (oldVal != cont.read);
          break;
        case 'msg':
          oldVal = cont.seq;
          cont.seq = max(cont.seq ?? 0, seq);
          if (cont.touched == null ||
              (ts != null && cont.touched!.isBefore(ts))) {
            cont.touched = ts;
          }
          doUpdate = (oldVal != cont.seq);
          break;
      }

      // Sanity checks.
      if ((cont.recv ?? 0) < (cont.read ?? 0)) {
        cont.recv = cont.read;
        doUpdate = true;
      }
      if ((cont.seq ?? 0) < (cont.recv ?? 0)) {
        cont.seq = cont.recv;
        if (cont.touched == null ||
            (ts != null && cont.touched!.isBefore(ts))) {
          cont.touched = ts;
        }
        doUpdate = true;
      }
      cont.unread = (cont.seq ?? 0) - (cont.read ?? 0);

      if (doUpdate && (cont.acs == null || !cont.acs!.isMuted(null))) {
        onContactUpdate.add(ContactUpdateEvent(what, cont));
      }
    }
  }

  /// Get cached read/received/message count for the given contact.
  int getMsgReadRecv(String contactName, String what) {
    var cont = _contacts[contactName];
    if (cont != null) {
      switch (what) {
        case 'recv':
          return cont.recv ?? 0;
        case 'read':
          return cont.read ?? 0;
        case 'msg':
          return cont.seq ?? 0;
      }
    }
    return 0;
  }

  /// Get a contact from cache
  TopicSubscription? getContact(String topicName) {
    return _contacts[topicName];
  }

  /// Get access mode of a given contact from cache
  AccessMode? getContactAccessMode(String? topicName) {
    if (topicName != null && topicName.isNotEmpty) {
      var cont = _contacts[topicName];
      return cont?.acs;
    }
    return null;
  }

  /// Check if contact is archived, i.e. contact.private.arch == true.
  bool? isContactArchived(String topicName) {
    var cont = _contacts[topicName];
    return cont != null
        ? ((cont.private && cont.private.arch) ? true : false)
        : null;
  }

  /// Get the user's credentials: email, phone, etc.
  List<Credential> getCredentials() {
    return _credentials;
  }

  /// Get All Moments or Get Moments of a topicName, from cache
  List<Moment>? getMomentsOrByUserId(String? topicName) {
    // if(_moments.isEmpty && _authService.userId != null){
    //   _moments = _cacheManager.get(momentsKey, _authService.userId!) ?? [];
    //   print('getMoments ${_authService.userId} ${_moments.toList()}');
    // }

    if (topicName == null) {
      return _moments;
    }
    return _moments.where((moment) => moment.userId == topicName).toList();
  }

  /// 获取指定动态的评论列表（从缓存）
  /// [momentId] 动态ID
  /// 返回该动态的评论列表，如果不存在则返回空列表
  List<MomentComment> getCommentsByMomentId(int momentId) {
    return _commentsMap[momentId] ?? [];
  }

  void _updateCached(TopicDescription object) {
    final userId = _authService.userId;
    if (userId == null) return;

    var cached = _cacheManager.getUser(userId);
    if (cached != null) {
      cached.acs = object.acs ?? cached.acs;
      cached.clear = object.clear ?? cached.clear;
      cached.created = object.created ?? cached.created;
      cached.deleted = cached.deleted ?? cached.deleted;
      cached.noForwarding = object.noForwarding ?? cached.noForwarding;
      cached.private = object.private ?? cached.private;
      cached.public = object.public ?? cached.public;
      cached.read = object.read ?? cached.read;
      cached.recv = object.recv ?? cached.recv;
      cached.touched = object.touched ?? cached.touched;
      cached.updated = object.updated ?? cached.updated;
      _cacheManager.putUser(userId, cached);
    } else {
      _cacheManager.putUser(userId, object.toSub(userId));
    }
  }
}
