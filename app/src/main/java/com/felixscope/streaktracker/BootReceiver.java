package com.felixscope.streaktracker;

import android.content.*;

public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            SharedPreferences p = context.getSharedPreferences("streaks", Context.MODE_PRIVATE);
            String time = p.getString("reminder_time", "21:30");
            int h = 21, m = 30;
            try { String[] parts = time.split(":"); h = Integer.parseInt(parts[0]); m = Integer.parseInt(parts[1]); } catch (Exception ignored) {}
            ReminderReceiver.scheduleDaily(context, h, m);
        }
    }
}
