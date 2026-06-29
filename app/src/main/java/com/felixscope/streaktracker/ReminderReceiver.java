package com.felixscope.streaktracker;

import android.app.*;
import android.content.*;
import android.os.Build;
import java.util.Calendar;

public class ReminderReceiver extends BroadcastReceiver {
    private static final String CHANNEL_ID = "streak_reminders";

    @Override public void onReceive(Context context, Intent intent) {
        showNotification(context, "Don't miss your streak 🔥", "Open Streak Tracker and finish today's checkboxes.");
        SharedPreferences p = context.getSharedPreferences("streaks", Context.MODE_PRIVATE);
        String time = p.getString("reminder_time", "21:30");
        int h = 21, m = 30;
        try { String[] parts = time.split(":"); h = Integer.parseInt(parts[0]); m = Integer.parseInt(parts[1]); } catch (Exception ignored) {}
        scheduleDaily(context, h, m);
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

    public static void scheduleDaily(Context c, int hour, int minute) {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, hour); cal.set(Calendar.MINUTE, minute); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0);
        if (cal.getTimeInMillis() <= System.currentTimeMillis()) cal.add(Calendar.DAY_OF_MONTH, 1);
        Intent i = new Intent(c, ReminderReceiver.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 0, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
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
