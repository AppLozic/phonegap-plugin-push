package com.adobe.phonegap.push;

import android.content.Context;

import android.app.IntentService;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import com.google.android.gms.gcm.GoogleCloudMessaging;
import com.google.android.gms.iid.InstanceID;
import com.applozic.mobicomkit.Applozic;
import com.applozic.mobicomkit.api.account.register.RegisterUserClientService;
import com.applozic.mobicomkit.api.account.register.RegistrationResponse;
import com.applozic.mobicomkit.api.account.user.MobiComUserPreference;

import java.io.IOException;

public class RegistrationIntentService extends IntentService implements PushConstants {
    public static final String LOG_TAG = "Push_RegistrationIntent";

    public RegistrationIntentService() {
        super(LOG_TAG);
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        SharedPreferences sharedPreferences = getApplicationContext().getSharedPreferences(COM_ADOBE_PHONEGAP_PUSH, Context.MODE_PRIVATE);

        try {
            InstanceID instanceID = InstanceID.getInstance(this);
            String senderID = sharedPreferences.getString(SENDER_ID, "");
            String token = instanceID.getToken(senderID,
                    GoogleCloudMessaging.INSTANCE_ID_SCOPE, null);
            PushPlugin.setRegistrationID(token);
            Log.i(LOG_TAG, "new GCM Registration Token: " + token);
        Applozic.getInstance(this).setDeviceRegistrationId(token);
       if (MobiComUserPreference.getInstance(this).isRegistered()) {
           try {
               RegistrationResponse registrationResponse = new RegisterUserClientService(this).updatePushNotificationId(token);
           } catch (Exception e) {
               e.printStackTrace();
           }
       }

        } catch (Exception e) {
            Log.d(LOG_TAG, "Failed to complete token refresh", e);
        }
    }
}
