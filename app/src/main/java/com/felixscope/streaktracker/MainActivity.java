package com.felixscope.streaktracker;

import android.Manifest;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.speech.RecognizerIntent;
import android.view.Gravity;
import android.view.View;
import android.widget.*;
import android.text.InputType;
import android.graphics.Typeface;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.*;

public class MainActivity extends android.app.Activity {
    private static final int REQ_SPEECH_STRANGER = 101;
    private static final int REQ_SPEECH_BIRTHDAY = 102;
    private static final int REQ_NOTIFICATIONS = 201;
    private SharedPreferences prefs;
    private LinearLayout list;
    private final Map<String, CheckBox> boxes = new LinkedHashMap<>();
    private EditText strangerComment, birthdayComment, scriptUrl, reminderTime;
    private TextView status, streakSummary, birthdayBox;
    private String today;

    private final String[][] habits = new String[][]{
            {"reading", "Reading"},
            {"eat_before_19", "Eating before 19:00"},
            {"up_before_8", "Get up before 08:00"},
            {"phone_off_22", "Shut off phone at 22:00"},
            {"pushups_10", "Do 10 pushups"},
            {"stranger_conversation", "Real-life conversation with a stranger"},
            {"got_her_number", "Plus: got her number"},
            {"call_close_one", "Phone call to a close one"},
            {"birthday_message_sent", "Birthday message sent"},
            {"birthday_called_instead", "Birthday: called instead"},
            {"cleaned_kitchen", "Cleaned kitchen"},
            {"cleaned_table", "Cleaned table"},
            {"cleaned_floor", "Cleaned floor"}
    };

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("streaks", MODE_PRIVATE);
        today = new SimpleDateFormat("yyyy-MM-dd", Locale.GERMANY).format(new Date());
        ReminderReceiver.ensureChannel(this);
        requestNotificationPermissionIfNeeded();
        buildUi();
        loadState();
        updateSummary();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(28, 28, 28, 48);
        scroll.addView(list);

        TextView title = new TextView(this);
        title.setText("Streak Tracker"); title.setTextSize(28); title.setTypeface(Typeface.DEFAULT_BOLD);
        list.addView(title);

        TextView date = new TextView(this);
        date.setText(today + "  ·  quick mode"); date.setTextColor(Color.DKGRAY); date.setTextSize(15);
        list.addView(date);

        streakSummary = new TextView(this); streakSummary.setTextSize(16); streakSummary.setPadding(0, 18, 0, 18);
        list.addView(streakSummary);

        for (String[] h : habits) addHabit(h[0], h[1]);

        addLabel("Stranger conversation comment");
        strangerComment = addCommentBox("Dictate or type what happened...");
        addButton("🎙 Speak stranger comment", v -> startSpeech(REQ_SPEECH_STRANGER));

        addLabel("Birthday actions");
        birthdayBox = new TextView(this);
        birthdayBox.setText("Tap 'Check birthdays' to load today's birthday events from Apps Script.");
        birthdayBox.setPadding(0, 8, 0, 8); list.addView(birthdayBox);
        addButton("🎂 Check birthdays today", v -> checkBirthdays());
        birthdayComment = addCommentBox("Birthday note / what you sent...");
        addButton("🎙 Speak birthday comment", v -> startSpeech(REQ_SPEECH_BIRTHDAY));

        addLabel("Sync + reminder settings");
        scriptUrl = addSingleLine("Google Apps Script Web App URL");
        reminderTime = addSingleLine("Reminder time, e.g. 21:30");
        reminderTime.setInputType(InputType.TYPE_CLASS_DATETIME);
        addButton("💾 Save + sync now", v -> { saveState(); syncNow(); });
        addButton("🔔 Schedule daily reminder", v -> { saveState(); scheduleReminder(); });
        addButton("🧪 Test notification", v -> ReminderReceiver.showNotification(this, "Don't miss your streak 🔥", "Open Streak Tracker and finish today's checkboxes."));

        status = new TextView(this); status.setPadding(0, 18, 0, 0); list.addView(status);
        setContentView(scroll);
    }

    private void addHabit(String key, String label) {
        CheckBox cb = new CheckBox(this);
        cb.setText(label); cb.setTextSize(20); cb.setPadding(0, 10, 0, 10);
        cb.setOnCheckedChangeListener((buttonView, isChecked) -> { saveState(); updateSummary(); });
        boxes.put(key, cb); list.addView(cb);
    }

    private void addLabel(String s) { TextView v = new TextView(this); v.setText(s); v.setTypeface(Typeface.DEFAULT_BOLD); v.setTextSize(18); v.setPadding(0, 24, 0, 4); list.addView(v); }
    private EditText addCommentBox(String hint) { EditText e = new EditText(this); e.setHint(hint); e.setMinLines(2); e.setGravity(Gravity.TOP); list.addView(e); return e; }
    private EditText addSingleLine(String hint) { EditText e = new EditText(this); e.setHint(hint); e.setSingleLine(true); list.addView(e); return e; }
    private void addButton(String text, View.OnClickListener l) { Button b = new Button(this); b.setText(text); b.setAllCaps(false); b.setOnClickListener(l); list.addView(b); }

    private void loadState() {
        for (String[] h : habits) boxes.get(h[0]).setChecked(prefs.getBoolean(today + ":" + h[0], false));
        strangerComment.setText(prefs.getString(today + ":stranger_comment", ""));
        birthdayComment.setText(prefs.getString(today + ":birthday_comment", ""));
        scriptUrl.setText(prefs.getString("script_url", ""));
        reminderTime.setText(prefs.getString("reminder_time", "21:30"));
    }

    private void saveState() {
        SharedPreferences.Editor e = prefs.edit();
        for (String[] h : habits) e.putBoolean(today + ":" + h[0], boxes.get(h[0]).isChecked());
        e.putString(today + ":stranger_comment", strangerComment.getText().toString());
        e.putString(today + ":birthday_comment", birthdayComment.getText().toString());
        e.putString("script_url", scriptUrl.getText().toString().trim());
        e.putString("reminder_time", reminderTime.getText().toString().trim());
        e.apply();
    }

    private void updateSummary() {
        int done = 0; for (CheckBox cb : boxes.values()) if (cb.isChecked()) done++;
        streakSummary.setText(done + "/" + boxes.size() + " checked today");
    }

    private void startSpeech(int requestCode) {
        Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault());
        i.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your comment");
        try { startActivityForResult(i, requestCode); } catch (Exception ex) { toast("Speech recognition not available on this phone."); }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode == RESULT_OK && data != null) {
            ArrayList<String> results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
            if (results != null && !results.isEmpty()) {
                EditText target = requestCode == REQ_SPEECH_BIRTHDAY ? birthdayComment : strangerComment;
                String old = target.getText().toString();
                target.setText(old.isEmpty() ? results.get(0) : old + "\n" + results.get(0));
                saveState();
            }
        }
    }

    private void syncNow() {
        String url = scriptUrl.getText().toString().trim();
        if (url.isEmpty()) { toast("Paste your Apps Script URL first."); return; }
        new Thread(() -> {
            try {
                postJson(url, dailyJson("saveDay"));
                runOnUiThread(() -> status.setText("Synced to Google Sheets."));
            } catch (Exception ex) { runOnUiThread(() -> status.setText("Sync failed: " + ex.getMessage())); }
        }).start();
    }

    private void checkBirthdays() {
        String url = scriptUrl.getText().toString().trim();
        if (url.isEmpty()) { toast("Paste your Apps Script URL first."); return; }
        new Thread(() -> {
            try {
                String response = postJson(url, "{\"action\":\"getBirthdays\",\"date\":\"" + today + "\"}");
                runOnUiThread(() -> birthdayBox.setText(response));
            } catch (Exception ex) { runOnUiThread(() -> birthdayBox.setText("Birthday check failed: " + ex.getMessage())); }
        }).start();
    }

    private String dailyJson(String action) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"action\":\"").append(action).append("\",\"date\":\"").append(today).append("\",");
        sb.append("\"habits\":{"); int i = 0;
        for (String[] h : habits) { if (i++ > 0) sb.append(','); sb.append('\"').append(h[0]).append("\":").append(boxes.get(h[0]).isChecked()); }
        sb.append("},\"stranger_comment\":\"").append(esc(strangerComment.getText().toString())).append("\",");
        sb.append("\"birthday_comment\":\"").append(esc(birthdayComment.getText().toString())).append("\"}");
        return sb.toString();
    }

    private String postJson(String target, String json) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(target).openConnection();
        c.setRequestMethod("POST"); c.setConnectTimeout(15000); c.setReadTimeout(15000); c.setDoOutput(true);
        c.setRequestProperty("Content-Type", "application/json; charset=utf-8");
        try (OutputStream os = c.getOutputStream()) { os.write(json.getBytes("UTF-8")); }
        Scanner sc = new Scanner(c.getInputStream(), "UTF-8").useDelimiter("\\A");
        return sc.hasNext() ? sc.next() : "OK";
    }

    private String esc(String s) { return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n"); }
    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_LONG).show(); }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIFICATIONS);
        }
    }

    private void scheduleReminder() {
        String t = reminderTime.getText().toString().trim();
        int hour = 21, minute = 30;
        try { String[] p = t.split(":"); hour = Integer.parseInt(p[0]); minute = Integer.parseInt(p[1]); } catch (Exception ignored) {}
        ReminderReceiver.scheduleDaily(this, hour, minute);
        status.setText("Daily reminder scheduled for " + String.format(Locale.GERMANY, "%02d:%02d", hour, minute) + ".");
    }
}
