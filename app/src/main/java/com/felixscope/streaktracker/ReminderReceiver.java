package com.felixscope.streaktracker;

import android.app.*;
import android.content.*;
import android.os.Build;
import android.os.PowerManager;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Random;

public class ReminderReceiver extends BroadcastReceiver {
    private static final String CHANNEL_ID = "streak_reminders";
    private static final String ACTION_PHONE_OFF_CHECK = "com.felixscope.streaktracker.PHONE_OFF_CHECK";

    @Override public void onReceive(Context context, Intent intent) {
        if (ACTION_PHONE_OFF_CHECK.equals(intent.getAction())) {
            checkAndMarkPhoneOff(context);
            schedulePhoneOffCheck(context);
            return;
        }
        showDueNotification(context);
        scheduleAll(context);
    }

    private static void checkAndMarkPhoneOff(Context context) {
        PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        if (!pm.isInteractive()) {
            String today = new SimpleDateFormat("yyyy-MM-dd", Locale.GERMANY).format(new Date());
            context.getSharedPreferences("streaks", Context.MODE_PRIVATE)
                    .edit().putBoolean(today + ":phone_off_22", true).apply();
        }
    }

    private static void showDueNotification(Context context) {
        SharedPreferences p = context.getSharedPreferences("streaks", Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        List<String> overdue = new ArrayList<>();
        addIfOverdue(p, overdue, "contact_oma", "Contact Oma", 14, now);
        addIfOverdue(p, overdue, "contact_mama", "Contact Mama", 14, now);
        addIfOverdue(p, overdue, "contact_ambi", "Contact Ambi", 14, now);
        addIfOverdue(p, overdue, "shaved", "Shaving", 3, now);

        if (!overdue.isEmpty()) {
            showNotification(context, "⚠ Once-every habits overdue", android.text.TextUtils.join(" · ", overdue));
            return;
        }

        String[] messages = {
                "A small action today keeps the streak alive.",
                "Check in with your habits—one tap at a time.",
                "Reading, moving, tidying, or connecting: pick one now.",
                "Open Habits Tracker and give today a little momentum."
        };
        showNotification(context, "Habits check-in", messages[new Random().nextInt(messages.length)]);
    }

    private static void addIfOverdue(SharedPreferences p, List<String> overdue, String key, String label, int days, long now) {
        long lastDone = p.getLong("last_done:" + key, p.getLong("tracking_started_at", now));
        long maximumAge = days * 24L * 60L * 60L * 1000L;
        long missed = (now - lastDone) / maximumAge;
        if (missed > 0) overdue.add(label + ": missed " + missed + (missed == 1 ? " time" : " times"));
    }

    public static void ensureChannel(Context c) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(CHANNEL_ID, "Streak reminders", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("Daily reminders to keep your habit streak alive");
            ((NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE)).createNotificationChannel(ch);
        }
    }

    public static void showNotification(Context c, String title, String text) {
        ensureChannel(c);
        Intent open = new Intent(c, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(c, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(c, CHANNEL_ID) : new Notification.Builder(c);
        b.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText(text).setContentIntent(pi).setAutoCancel(true);
        ((NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE)).notify(2200, b.build());
    }

    public static void scheduleAll(Context c) {
        scheduleDaily(c, 10, 0, 1000);
        scheduleDaily(c, 17, 30, 1001);
        scheduleDaily(c, 21, 0, 1002);
        schedulePhoneOffCheck(c);
    }

    public static void schedulePhoneOffCheck(Context c) {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, 22); cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0);
        if (cal.getTimeInMillis() <= System.currentTimeMillis()) cal.add(Calendar.DAY_OF_MONTH, 1);
        Intent i = new Intent(c, ReminderReceiver.class);
        i.setAction(ACTION_PHONE_OFF_CHECK);
        PendingIntent pi = PendingIntent.getBroadcast(c, 2200, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
        } else if (Build.VERSION.SDK_INT >= 23) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
        }
    }

    private static void scheduleDaily(Context c, int hour, int minute, int requestCode) {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, hour); cal.set(Calendar.MINUTE, minute); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0);
        if (cal.getTimeInMillis() <= System.currentTimeMillis()) cal.add(Calendar.DAY_OF_MONTH, 1);
        Intent i = new Intent(c, ReminderReceiver.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, requestCode, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        AlarmManager am = (AlarmManager)c.getSystemService(Context.ALARM_SERVICE);
        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
        } else if (Build.VERSION.SDK_INT >= 23) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(), pi);
        }
    }
}
