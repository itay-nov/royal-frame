import 'dart:io';

import 'package:flutter/services.dart';

import 'rating_invitation_platform.dart';

RatingInvitationPlatformAdapter createPlatformAdapter() => Platform.isAndroid
    ? AndroidRatingInvitationAdapter()
    : const _UnsupportedRatingInvitationAdapter();

class AndroidRatingInvitationAdapter
    implements RatingInvitationPlatformAdapter {
  AndroidRatingInvitationAdapter({
    MethodChannel channel = const MethodChannel(
      'com.itay.royalframegame/in_app_review',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  RatingInvitationPlatform get platform => RatingInvitationPlatform.android;

  @override
  Future<bool> requestAndroidReview() async {
    try {
      return await _channel.invokeMethod<bool>('requestReview') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> launchWebListing() async => false;
}

class _UnsupportedRatingInvitationAdapter
    implements RatingInvitationPlatformAdapter {
  const _UnsupportedRatingInvitationAdapter();

  @override
  RatingInvitationPlatform get platform => RatingInvitationPlatform.unsupported;

  @override
  Future<bool> launchWebListing() async => false;

  @override
  Future<bool> requestAndroidReview() async => false;
}
