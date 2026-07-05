package com.felixscope.habits_tracker;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CallLog;
import android.provider.ContactsContract;
import android.provider.Telephony;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

public final class CommunicationTracker {
    private static final long LOOKBACK = 14L * 24L * 60L * 60L * 1000L;
    private static final String PREFS = "communication_tracking";

    private CommunicationTracker() {}

    public static Map<String, Long> scan(Context context) {
        if (has(context, Manifest.permission.READ_CALL_LOG)) scanCalls(context);
        if (has(context, Manifest.permission.READ_SMS)) scanSentSms(context);
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Map<String, Long> result = new HashMap<>();
        for (String key : new String[]{"contact_oma", "contact_mama", "contact_ambi"}) {
            result.put(key, prefs.getLong("last_done:" + key, 0));
        }
        return result;
    }

    private static boolean has(Context context, String permission) {
        return android.os.Build.VERSION.SDK_INT < 23 || context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
    }

    private static void scanCalls(Context context) {
        String[] columns = {CallLog.Calls.CACHED_NAME, CallLog.Calls.NUMBER, CallLog.Calls.DATE};
        try (Cursor cursor = context.getContentResolver().query(CallLog.Calls.CONTENT_URI, columns,
                CallLog.Calls.DATE + ">=?", new String[]{String.valueOf(System.currentTimeMillis() - LOOKBACK)},
                CallLog.Calls.DATE + " DESC")) {
            if (cursor == null) return;
            while (cursor.moveToNext()) {
                String name = cursor.getString(0);
                if (name == null || name.isEmpty()) name = resolveName(context, cursor.getString(1));
                recordMatch(context, name, cursor.getLong(2));
            }
        } catch (SecurityException ignored) {}
    }

    private static void scanSentSms(Context context) {
        String[] columns = {Telephony.Sms.ADDRESS, Telephony.Sms.DATE};
        try (Cursor cursor = context.getContentResolver().query(Telephony.Sms.Sent.CONTENT_URI, columns,
                Telephony.Sms.DATE + ">=?", new String[]{String.valueOf(System.currentTimeMillis() - LOOKBACK)},
                Telephony.Sms.DATE + " DESC")) {
            if (cursor == null) return;
            while (cursor.moveToNext()) recordMatch(context, resolveName(context, cursor.getString(0)), cursor.getLong(1));
        } catch (SecurityException ignored) {}
    }

    private static String resolveName(Context context, String number) {
        if (number == null || !has(context, Manifest.permission.READ_CONTACTS)) return number == null ? "" : number;
        Uri uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number));
        try (Cursor cursor = context.getContentResolver().query(uri,
                new String[]{ContactsContract.PhoneLookup.DISPLAY_NAME}, null, null, null)) {
            return cursor != null && cursor.moveToFirst() ? cursor.getString(0) : number;
        } catch (SecurityException ignored) { return number; }
    }

    static void recordMatch(Context context, String text, long timestamp) {
        if (text == null) return;
        String normalized = text.toLowerCase(Locale.ROOT);
        String key = normalized.contains("oma") ? "contact_oma" :
                normalized.contains("mama") ? "contact_mama" :
                normalized.contains("ambi") ? "contact_ambi" : null;
        if (key == null) return;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long previous = prefs.getLong("last_done:" + key, 0);
        if (timestamp > previous) prefs.edit().putLong("last_done:" + key, timestamp).apply();
    }
}
