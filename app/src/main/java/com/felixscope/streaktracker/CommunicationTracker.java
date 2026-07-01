package com.felixscope.streaktracker;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CallLog;
import android.provider.ContactsContract;
import android.provider.Telephony;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public final class CommunicationTracker {
    private static final long LOOKBACK = 14L * 24L * 60L * 60L * 1000L;

    private CommunicationTracker() {}

    public static void scan(Context context) {
        if (android.os.Build.VERSION.SDK_INT < 23 || context.checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
            scanCalls(context);
        }
        if (android.os.Build.VERSION.SDK_INT < 23 || context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) {
            scanSentSms(context);
        }
    }

    private static void scanCalls(Context context) {
        long since = System.currentTimeMillis() - LOOKBACK;
        String[] columns = {CallLog.Calls.CACHED_NAME, CallLog.Calls.NUMBER, CallLog.Calls.DATE};
        try (Cursor cursor = context.getContentResolver().query(CallLog.Calls.CONTENT_URI, columns,
                CallLog.Calls.DATE + ">=?", new String[]{String.valueOf(since)}, CallLog.Calls.DATE + " DESC")) {
            if (cursor == null) return;
            while (cursor.moveToNext()) {
                String name = cursor.getString(0);
                if (name == null || name.isEmpty()) name = resolveName(context, cursor.getString(1));
                recordMatch(context, name, cursor.getLong(2));
            }
        } catch (SecurityException ignored) {}
    }

    private static void scanSentSms(Context context) {
        long since = System.currentTimeMillis() - LOOKBACK;
        String[] columns = {Telephony.Sms.ADDRESS, Telephony.Sms.DATE};
        try (Cursor cursor = context.getContentResolver().query(Telephony.Sms.Sent.CONTENT_URI, columns,
                Telephony.Sms.DATE + ">=?", new String[]{String.valueOf(since)}, Telephony.Sms.DATE + " DESC")) {
            if (cursor == null) return;
            while (cursor.moveToNext()) recordMatch(context, resolveName(context, cursor.getString(0)), cursor.getLong(1));
        } catch (SecurityException ignored) {}
    }

    private static String resolveName(Context context, String number) {
        if (number == null) return "";
        if (android.os.Build.VERSION.SDK_INT >= 23 && context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return number;
        Uri uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number));
        try (Cursor cursor = context.getContentResolver().query(uri,
                new String[]{ContactsContract.PhoneLookup.DISPLAY_NAME}, null, null, null)) {
            return cursor != null && cursor.moveToFirst() ? cursor.getString(0) : number;
        } catch (SecurityException ignored) { return number; }
    }

    static void recordMatch(Context context, String text, long timestamp) {
        if (text == null) return;
        String normalized = text.toLowerCase(Locale.ROOT);
        String key = null;
        if (normalized.contains("oma")) key = "contact_oma";
        else if (normalized.contains("mama")) key = "contact_mama";
        else if (normalized.contains("ambi")) key = "contact_ambi";
        if (key == null) return;
        SharedPreferences prefs = context.getSharedPreferences("streaks", Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();
        long previous = prefs.getLong("last_done:" + key, 0);
        if (timestamp > previous) editor.putLong("last_done:" + key, timestamp);
        String msgDay = new SimpleDateFormat("yyyy-MM-dd", Locale.GERMANY).format(new Date(timestamp));
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.GERMANY).format(new Date());
        if (msgDay.equals(today)) editor.putBoolean(today + ":" + key, true);
        editor.apply();
    }
}
