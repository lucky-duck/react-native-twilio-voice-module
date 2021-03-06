package com.twiliovoicemodule;

import android.annotation.TargetApi;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.ProcessLifecycleOwner;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;

import com.facebook.react.ReactApplication;
import com.facebook.react.ReactInstanceManager;
import com.facebook.react.bridge.ReactContext;
import com.twilio.voice.CallInvite;

import java.util.Map;

public class IncomingCallNotificationService extends Service {

    private static final String TAG = IncomingCallNotificationService.class.getSimpleName();

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent.getAction();

        if (action != null) {
            CallInvite callInvite = intent.getParcelableExtra(Constants.INCOMING_CALL_INVITE);
            int notificationId = intent.getIntExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, 0);
            switch (action) {
                case Constants.ACTION_INCOMING_CALL:
                    handleIncomingCall(callInvite, notificationId);
                    break;
                case Constants.ACTION_ACCEPT:
                    accept(callInvite, notificationId);
                    break;
                case Constants.ACTION_REJECT:
                    reject(callInvite);
                    break;
                case Constants.ACTION_CANCEL_CALL:
                    handleCancelledCall(intent);
                    break;
                default:
                    break;
            }
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private Notification createNotification(CallInvite callInvite, int notificationId, int channelImportance) {
//        ActivityManager am = (ActivityManager)getApplicationContext().getSystemService(Context.ACTIVITY_SERVICE);
//        ComponentName currentActivity = am.getRunningTasks(1).get(0).topActivity;
//        ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//        ReactContext context = mReactInstanceManager.getCurrentReactContext();
        Intent intent = new Intent();
        intent.setClassName("com.anyonemobile", "com.anyonemobile.MainActivity");
//        Intent intent = new Intent(context, IncomingCallNotificationService.class);
        intent.setAction(Constants.ACTION_INCOMING_CALL_NOTIFICATION);
        intent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
//        intent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);
        intent.putExtra("call_sid", callInvite.getCallSid());
        intent.putExtra("call_from", callInvite.getFrom());
        intent.putExtra("call_to", callInvite.getTo());
        
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent =
                PendingIntent.getActivity(this, notificationId, intent, PendingIntent.FLAG_UPDATE_CURRENT);
        /*
         * Pass the notification id and call sid to use as an identifier to cancel the
         * notification later
         */
        Bundle extras = new Bundle();
        extras.putString(Constants.CALL_SID_KEY, callInvite.getCallSid());
        Map<String, String> customParameters = callInvite.getCustomParameters();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return buildNotification(customParameters.getOrDefault("fromName", "Someone") + " is calling about " + customParameters.getOrDefault("topicTitle", "something"),
                    pendingIntent,
                    extras,
                    callInvite,
                    notificationId,
                    createChannel(channelImportance));
        } else {
            //noinspection deprecation

            return new NotificationCompat.Builder(this)
                    .setSmallIcon(R.drawable.ic_call_end_white_24dp)
                    .setContentTitle(getString(R.string.app_name))
                    .setContentText((customParameters.containsKey("fromName") ? customParameters.get("fromName") : "Someone") + " is calling about " + (customParameters.containsKey("topicTitle") ? customParameters.get("topicTitle") : "something"))
                    .setAutoCancel(true)
                    .setExtras(extras)
                    .setContentIntent(pendingIntent)
                    .setGroup("test_app_notification")
                    .setColor(Color.rgb(214, 10, 37)).build();
        }
    }

    /**
     * Build a notification.
     *
     * @param text          the text of the notification
     * @param pendingIntent the body, pending intent for the notification
     * @param extras        extras passed with the notification
     * @return the builder
     */
    @TargetApi(Build.VERSION_CODES.O)
    private Notification buildNotification(String text, PendingIntent pendingIntent, Bundle extras,
                                           final CallInvite callInvite,
                                           int notificationId,
                                           String channelId) {

//        ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//        ReactContext context = mReactInstanceManager.getCurrentReactContext();
        Intent rejectIntent = new Intent(getApplicationContext(), IncomingCallNotificationService.class);
        rejectIntent.setAction(Constants.ACTION_REJECT);
        // rejectIntent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);
//        rejectIntent.putExtra("call_sid", callInvite.getCallSid());
//        rejectIntent.putExtra("call_from", callInvite.getFrom());
//        rejectIntent.putExtra("call_to", callInvite.getTo());
        rejectIntent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);

        rejectIntent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
        PendingIntent piRejectIntent = PendingIntent.getService(getApplicationContext(), 1201, rejectIntent, PendingIntent.FLAG_UPDATE_CURRENT);

        Intent acceptIntent = new Intent(getApplicationContext(), IncomingCallNotificationService.class);
        acceptIntent.setAction(Constants.ACTION_ACCEPT);
        // acceptIntent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);
//        acceptIntent.putExtra("call_sid", callInvite.getCallSid());
//        acceptIntent.putExtra("call_from", callInvite.getFrom());
//        acceptIntent.putExtra("call_to", callInvite.getTo());
        acceptIntent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);

        acceptIntent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
        PendingIntent piAcceptIntent = PendingIntent.getService(getApplicationContext(), 1200, acceptIntent, PendingIntent.FLAG_UPDATE_CURRENT);

        Notification.Builder builder =
                new Notification.Builder(getApplicationContext(), channelId)
                        .setSmallIcon(R.drawable.ic_call_end_white_24dp)
                        .setContentTitle(getString(R.string.app_name))
                        .setContentText(text)
                        .setCategory(Notification.CATEGORY_CALL)
                        .setFullScreenIntent(pendingIntent, true)
                        .setExtras(extras)
                        .addAction(R.drawable.ic_call_green, "Accept", piAcceptIntent)
                        .addAction(R.drawable.ic_cancel_sexy, "Decline", piRejectIntent)
                        .setAutoCancel(true)
                        .setFullScreenIntent(pendingIntent, true);

        return builder.build();
    }

    @TargetApi(Build.VERSION_CODES.O)
    private String createChannel(int channelImportance) {
        NotificationChannel callInviteChannel = new NotificationChannel(Constants.VOICE_CHANNEL_HIGH_IMPORTANCE,
                "Primary Voice Channel", NotificationManager.IMPORTANCE_HIGH);
        String channelId = Constants.VOICE_CHANNEL_HIGH_IMPORTANCE;

        if (channelImportance == NotificationManager.IMPORTANCE_LOW) {
            callInviteChannel = new NotificationChannel(Constants.VOICE_CHANNEL_LOW_IMPORTANCE,
                    "Primary Voice Channel", NotificationManager.IMPORTANCE_LOW);
            channelId = Constants.VOICE_CHANNEL_LOW_IMPORTANCE;
        }
        callInviteChannel.setLightColor(Color.GREEN);
        callInviteChannel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.createNotificationChannel(callInviteChannel);

        return channelId;
    }

    private void accept(CallInvite callInvite, int notificationId) {
        endForeground();
        if (isAppVisible()) {
            Log.i(TAG, "accept - app is visible.");
        }
//        ActivityManager am = (ActivityManager)getApplicationContext().getSystemService(Context.ACTIVITY_SERVICE);
//        ComponentName currentActivity = am.getRunningTasks(1).get(0).topActivity;
//        ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//        ReactContext context = mReactInstanceManager.getCurrentReactContext();
        Intent activeCallIntent = new Intent();
        activeCallIntent.setClassName("com.anyonemobile", "com.anyonemobile.MainActivity");
//        Intent activeCallIntent = new Intent(context, MainActivity.class);
        activeCallIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        activeCallIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        //activeCallIntent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);
        activeCallIntent.putExtra("call_sid", callInvite.getCallSid());
        activeCallIntent.putExtra("call_from", callInvite.getFrom());
        activeCallIntent.putExtra("call_to", callInvite.getTo());
        activeCallIntent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
        activeCallIntent.setAction(Constants.ACTION_ACCEPT);
        startActivity(activeCallIntent);
//        this.startActivity(activeCallIntent);
    }

    private void reject(CallInvite callInvite) {
        endForeground();
//        ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//        ReactContext context = mReactInstanceManager.getCurrentReactContext();
        callInvite.reject(getApplicationContext());
    }

    private void handleCancelledCall(Intent intent) {
        endForeground();
//        ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//        ReactContext context = mReactInstanceManager.getCurrentReactContext();
        LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(intent);
    }

    private void handleIncomingCall(CallInvite callInvite, int notificationId) {

        if (callInvite == null)
            return;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            setCallInProgressNotification(callInvite, notificationId);
        }
        sendCallInviteToActivity(callInvite, notificationId);
    }

    private void endForeground() {
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.ECLAIR) {
            stopForeground(true);
//        }
    }

    @TargetApi(Build.VERSION_CODES.O)
    private void setCallInProgressNotification(CallInvite callInvite, int notificationId) {

        if (callInvite == null)
            return;

        if (isAppVisible()) {
            Log.i(TAG, "setCallInProgressNotification - app is visible.");
            startForeground(notificationId, createNotification(callInvite, notificationId, NotificationManager.IMPORTANCE_LOW));
        } else {
            Log.i(TAG, "setCallInProgressNotification - app is NOT visible.");
            startForeground(notificationId, createNotification(callInvite, notificationId, NotificationManager.IMPORTANCE_HIGH));
        }
    }

    /*
     * Send the CallInvite to the VoiceActivity. Start the activity if it is not running already.
     */
    private void sendCallInviteToActivity(CallInvite callInvite, int notificationId) {
//        if (Build.VERSION.SDK_INT >= 29 && !isAppVisible()) {
//            return;
//        }
        Intent intent = new Intent();
        intent.setClassName("com.anyonemobile", "com.anyonemobile.MainActivity");
        intent.setAction(Constants.ACTION_INCOMING_CALL);
        intent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
        // intent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);

        intent.putExtra("call_sid", callInvite.getCallSid());
        intent.putExtra("call_from", callInvite.getFrom());
        intent.putExtra("call_to", callInvite.getTo());

        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        this.startActivity(intent);

        Intent i = new Intent(Constants.ACTION_INCOMING_CALL);
        i.putExtra("call_invite", callInvite);
//        ReactInstanceManager mReactInstanceManager = ((ReactApplication) getApplication()).getReactNativeHost().getReactInstanceManager();
//        ReactContext context = mReactInstanceManager.getCurrentReactContext();
        new android.os.Handler().postDelayed(
                new Runnable() {
                    public void run() {
                        LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(i);
                    }
                },
                3000);

//        ActivityManager am = (ActivityManager)getApplicationContext().getSystemService(Context.ACTIVITY_SERVICE);
//        ComponentName currentActivity = am.getRunningTasks(1).get(0).topActivity;
//        Intent intent = new Intent(this, currentActivity.getClass());
//        intent.setAction(Constants.ACTION_INCOMING_CALL);
//        intent.putExtra(Constants.INCOMING_CALL_NOTIFICATION_ID, notificationId);
//        intent.putExtra(Constants.INCOMING_CALL_INVITE, callInvite);
//        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
//        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
//        this.startActivity(intent);
    }

    private boolean isAppVisible() {
        return ProcessLifecycleOwner
                .get()
                .getLifecycle()
                .getCurrentState()
                .isAtLeast(Lifecycle.State.STARTED);
    }
}
