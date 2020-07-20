package com.twiliovoicemodule.fcm;

import android.content.Intent;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;

import com.facebook.react.ReactApplication;
import com.facebook.react.ReactInstanceManager;
import com.facebook.react.bridge.ReactContext;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import com.twilio.voice.CallInvite;
import com.twilio.voice.CallException;
import com.twilio.voice.CancelledCallInvite;
import com.twilio.voice.MessageListener;
import com.twilio.voice.Voice;
import com.twiliovoicemodule.Constants;
import com.twiliovoicemodule.IncomingCallNotificationService;

import java.util.Map;

public class VoiceCallFCMService extends FirebaseMessagingService {
    public static final String ACTION_FCM_TOKEN_REFRESHED = "fcmTokenRefreshed";
    public static final String ACTION_INCOMING_CALL = "incomingCall";
    public static final String ACTION_INCOMING_CALL_CANCELLED = "incomingCallCancelled";
    private static final String TAG = "VoiceFCMService";
    @Override
    public void onCreate() {
        super.onCreate();
    }

    @Override
    public void onNewToken(String token) {
        super.onNewToken(token);
        Intent intent = new Intent(ACTION_FCM_TOKEN_REFRESHED);
        intent.putExtra("fcm_token", token);
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent);
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        Log.d(TAG, "Received onMessageReceived()");
        Log.d(TAG, "Bundle data: " + remoteMessage.getData());
        Log.d(TAG, "From: " + remoteMessage.getFrom());

        // Check if message contains a data payload.
        if (remoteMessage.getData().size() > 0) {
            boolean valid = Voice.handleMessage(this, remoteMessage.getData(), new MessageListener() {
                @Override
                public void onCallInvite(@NonNull CallInvite callInvite) {
                    final int notificationId = (int) System.currentTimeMillis();
                    handleInvite(callInvite, notificationId);
                }

                @Override
                public void onCancelledCallInvite(@NonNull CancelledCallInvite cancelledCallInvite, @Nullable CallException callException) {
                    handleCanceledCallInvite(cancelledCallInvite);
                }
            });

            if (!valid) {
                Log.e(TAG, "The message was not a valid Twilio Voice SDK payload: " +
                        remoteMessage.getData());
            }
        }
//        if (remoteMessage.getData().size() > 0) {
//            Map<String, String> data = remoteMessage.getData();
//            Voice.handleMessage(data, new MessageListener() {
//                @Override
//                public void onCallInvite(@NonNull CallInvite callInvite) {
//                    Intent i = new Intent(ACTION_INCOMING_CALL);
//                    i.putExtra("call_invite", callInvite);
//                    ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//                    ReactContext context = mReactInstanceManager.getCurrentReactContext();
//                    LocalBroadcastManager.getInstance(context).sendBroadcast(i);
//                }
//
//                @Override
//                public void onCancelledCallInvite(@NonNull CancelledCallInvite cancelledCallInvite) {
//                    Intent i = new Intent(ACTION_INCOMING_CALL_CANCELLED);
//                    i.putExtra("cancelled_call_invite", cancelledCallInvite);
//                    ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//                    ReactContext context = mReactInstanceManager.getCurrentReactContext();
//                    LocalBroadcastManager.getInstance(context).sendBroadcast(i);
//                }
//            });
//        }
    }

    private void handleInvite(CallInvite callInvite, int notificationId) {
        Intent intent = new Intent(this, IncomingCallNotificationService.class);
        intent.setAction(Constants.ACTION_INCOMING_CALL);
        intent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
        intent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);

        startService(intent);
    }

    private void handleCanceledCallInvite(CancelledCallInvite cancelledCallInvite) {
        Intent intent = new Intent(this, IncomingCallNotificationService.class);
        intent.setAction(Constants.ACTION_CANCEL_CALL);
        intent.putExtra(Constants.CANCELLED_CALL_INVITE, cancelledCallInvite);

        startService(intent);
    }
}
