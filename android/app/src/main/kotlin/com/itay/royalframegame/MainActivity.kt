package com.itay.royalframegame

import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val reviewChannel = "com.itay.royalframegame/in_app_review"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            reviewChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestReview") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val reviewManager = ReviewManagerFactory.create(this)
                reviewManager.requestReviewFlow().addOnCompleteListener { request ->
                    if (!request.isSuccessful) {
                        result.success(false)
                        return@addOnCompleteListener
                    }

                    try {
                        reviewManager
                            .launchReviewFlow(this, request.result)
                            .addOnCompleteListener { launch ->
                                // Google intentionally provides no signal for
                                // dialog display or review submission.
                                result.success(launch.isSuccessful)
                            }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }
}
