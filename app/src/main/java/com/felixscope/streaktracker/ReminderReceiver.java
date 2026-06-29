package com.felixscope.streaktracker;

import android.app.*;
import android.content.*;
import android.os.Build;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Random;

public class ReminderReceiver extends BroadcastReceiver {
    private static final String CHANNEL_ID = "streak_reminders";

    @Override public void onReceive(Context context, Intent intent) {
        showDueNotification(context);
        scheduleAll(context);
    }

    private static void showDueNotification(Context context) {
        SharedPreferences p = context.getSharedPreferences("streaks", Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        List<String> overdue = new ArrayList<>();
        addIfOverdue(p, overdue, "contact_oma", "Oma", 14, now);
        addIfOverdue(p, overdue, "contact_mama", "Mama", 14, now);
        addIfOverdue(p, overdue, "contact_ambi", "Ambi", 14, now);
        addIfOverdue(p, overdue, "shaved", "shaving", 3, now);

        if (!overdue.isEmpty()) {
            showNotification(context, "A check-in is due", "Time for: " + android.text.TextUtils.join(", ", overdue) + ".");
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
        long lastDone = p.getLong("last_done:" + key, 0);
        long maximumAge = days * 24L * 60L * 60L * 1000L;
        if (lastDone == 0 || now - lastDone >= maximumAge) overdue.add(label);
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
