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
import android.graphics.BitmapFactory;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.app.AlertDialog;
import android.content.ClipData;
import androidx.core.content.FileProvider;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.OutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.text.SimpleDateFormat;
import java.util.*;

public class MainActivity extends android.app.Activity {
    private static final int REQ_SPEECH_STRANGER = 101;
    private static final int REQ_SPEECH_BIRTHDAY = 102;
    private static final int REQ_NOTIFICATIONS = 201;
    private static final int REQ_COMMUNICATION_HISTORY = 202;
    private static final int REQ_BOOK_PHOTO = 301;
    private static final String DEFAULT_SCRIPT_URL = "https://script.google.com/macros/s/AKfycby1swd2M1TqpzPSDcCV4aV-rXqDXZ0G3nS8V4lN0YqLGCSSUI00bh1tqUML_NjD9aox/exec";
    private SharedPreferences prefs;
    private LinearLayout list;
    private final Map<String, CheckBox> boxes = new LinkedHashMap<>();
    private final Map<String, Integer> counters = new LinkedHashMap<>();
    private final Map<String, TextView> counterViews = new LinkedHashMap<>();
    private EditText strangerComment, courageComment, boardGameComment, sportsComment, birthdayComment, scriptUrl;
    private TextView status, streakSummary, birthdayBox;
    private TextView readingSummary;
    private ImageView latestBookPhoto;
    private File pendingBookPhoto;
    private String today;
    private boolean loadingState;

    private final String[][] habits = new String[][]{
            {"eat_before_19", "Eating before 19:00"},
            {"up_before_8", "Get up before 08:00"},
            {"phone_off_22", "Shut off phone at 22:00"},
            {"call_close_one", "Phone call to a close one"},
            {"birthday_message_sent", "Birthday message sent"},
            {"birthday_called_instead", "Birthday: called instead"},
            {"journaling", "Journaling"},
            {"courage", "Sich was trauen", "Etwas tun, das Mut kostet oder außerhalb deiner Komfortzone liegt."},
            {"board_game", "Play a board game"},
            {"sports", "Sports"},
            {"contact_oma", "Called or messaged Oma", "Do this at least once every 14 days."},
            {"contact_mama", "Called or messaged Mama", "Do this at least once every 14 days."},
            {"contact_ambi", "Called or messaged Ambi", "Do this at least once every 14 days."},
            {"no_porn", "No Prn"},
            {"shaved", "Shaved", "Do this at least once every 3 days."},
            {"lights_off_2245", "Bedtime: lights off by 22:45"},
            {"cleaned_kitchen", "Cleaned kitchen"},
            {"cleaned_table", "Cleaned table"},
            {"cleaned_floor", "Cleaned floor"}
    };

    private final String[][] repeatableHabits = new String[][]{
            {"reading", "Reading"},
            {"pushups_10", "Sets of 10 pushups"},
            {"got_her_number", "Got her number"},
            {"stranger_conversation", "Conversation with a stranger"},
            {"housework", "Housework"},
            {"stretching", "Stretching"},
            {"walking", "Walk around"}
    };

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("streaks", MODE_PRIVATE);
        seedHistoricalEntries();
        today = new SimpleDateFormat("yyyy-MM-dd", Locale.GERMANY).format(new Date());
        ReminderReceiver.ensureChannel(this);
        requestNotificationPermissionIfNeeded();
        ReminderReceiver.scheduleAll(this);
        buildUi();
        loadState();
        updateSummary();
    }

    private void seedHistoricalEntries() {
        if (!prefs.getBoolean("seeded:2026-06-29:lights_off_2245", false)) {
            prefs.edit()
                    .putBoolean("2026-06-29:lights_off_2245", true)
                    .putString("2026-06-29:lights_off_time", "22:45")
                    .putBoolean("seeded:2026-06-29:lights_off_2245", true)
                    .apply();
        }
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

        for (String[] h : habits) addHabit(h[0], h[1], h.length > 2 ? h[2] : null);

        addLabel("Repeatable habits");
        for (String[] h : repeatableHabits) addCounter(h[0], h[1]);

        addLabel("Finished books");
        readingSummary = new TextView(this);
        readingSummary.setTextSize(17); readingSummary.setPadding(0, 4, 0, 8);
        list.addView(readingSummary);
        latestBookPhoto = new ImageView(this);
        latestBookPhoto.setAdjustViewBounds(true); latestBookPhoto.setMaxHeight(420);
        list.addView(latestBookPhoto);
        addButton("📷 Photograph a finished book", v -> captureFinishedBook());

        addLabel("Stranger conversation comment");
        strangerComment = addCommentBox("Dictate or type what happened...");
        addButton("🎙 Speak stranger comment", v -> startSpeech(REQ_SPEECH_STRANGER));

        addLabel("Sich was trauen – Kommentar");
        courageComment = addCommentBox("Was hast du dich getraut?");

        addLabel("Board game description");
        boardGameComment = addCommentBox("Which board game did you play?");

        addLabel("Sports description");
        sportsComment = addCommentBox("What sport or exercise did you do?");

        addLabel("Birthday actions");
        birthdayBox = new TextView(this);
        birthdayBox.setText("Tap 'Check birthdays' to load today's birthday events from Apps Script.");
        birthdayBox.setPadding(0, 8, 0, 8); list.addView(birthdayBox);
        addButton("🎂 Check birthdays today", v -> checkBirthdays());
        birthdayComment = addCommentBox("Birthday note / what you sent...");
        addButton("🎙 Speak birthday comment", v -> startSpeech(REQ_SPEECH_BIRTHDAY));

        addLabel("Sync + reminder settings");
        scriptUrl = addSingleLine("Google Apps Script Web App URL");
        TextView reminderSchedule = new TextView(this);
        reminderSchedule.setText("Daily reminders: 10:00, 17:30, 21:00"); reminderSchedule.setTextSize(16);
        list.addView(reminderSchedule);
        addButton("💾 Save + sync now", v -> { saveState(); syncNow(); });
        addButton("🔔 Schedule 3 daily reminders", v -> { saveState(); scheduleReminders(); });
        addButton("📱 Enable WhatsApp notification access", v ->
                startActivity(new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")));
        addButton("🧪 Test notification", v -> ReminderReceiver.showNotification(this, "Don't miss your streak 🔥", "Open Streak Tracker and finish today's checkboxes."));

        status = new TextView(this); status.setPadding(0, 18, 0, 0); list.addView(status);
        setContentView(scroll);
    }

    private void addHabit(String key, String label, String description) {
        CheckBox cb = new CheckBox(this);
        cb.setText(label); cb.setTextSize(20); cb.setPadding(0, 10, 0, 10);
        cb.setOnCheckedChangeListener((buttonView, isChecked) -> {
            if (!loadingState) {
                recordRecurringCompletion(key, isChecked);
                saveState(); updateSummary();
            }
        });
        boxes.put(key, cb); list.addView(cb);
        if (description != null) {
            TextView detail = new TextView(this);
            detail.setText(description); detail.setTextSize(14); detail.setTextColor(Color.DKGRAY);
            detail.setPadding(48, 0, 0, 10); list.addView(detail);
        }
    }

    private void addCounter(String key, String label) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, 8, 0, 8);

        TextView name = new TextView(this);
        name.setText(label); name.setTextSize(20);
        row.addView(name, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));

        Button minus = new Button(this); minus.setText("−"); minus.setAllCaps(false);
        TextView count = new TextView(this); count.setText("0"); count.setTextSize(20); count.setGravity(Gravity.CENTER); count.setMinWidth(70);
        Button plus = new Button(this); plus.setText("+"); plus.setAllCaps(false);

        counters.put(key, 0); counterViews.put(key, count);
        minus.setOnClickListener(v -> changeCounter(key, -1));
        plus.setOnClickListener(v -> changeCounter(key, 1));
        row.addView(minus); row.addView(count); row.addView(plus);
        list.addView(row);
    }

    private void changeCounter(String key, int change) {
        int value = Math.max(0, counters.get(key) + change);
        counters.put(key, value);
        counterViews.get(key).setText(String.valueOf(value));
        saveState(); updateSummary();
    }

    private void addLabel(String s) { TextView v = new TextView(this); v.setText(s); v.setTypeface(Typeface.DEFAULT_BOLD); v.setTextSize(18); v.setPadding(0, 24, 0, 4); list.addView(v); }
    private EditText addCommentBox(String hint) { EditText e = new EditText(this); e.setHint(hint); e.setMinLines(2); e.setGravity(Gravity.TOP); list.addView(e); return e; }
    private EditText addSingleLine(String hint) { EditText e = new EditText(this); e.setHint(hint); e.setSingleLine(true); list.addView(e); return e; }
    private void addButton(String text, View.OnClickListener l) { Button b = new Button(this); b.setText(text); b.setAllCaps(false); b.setOnClickListener(l); list.addView(b); }

    private void loadState() {
        loadingState = true;
        for (String[] h : habits) boxes.get(h[0]).setChecked(prefs.getBoolean(today + ":" + h[0], false));
        for (String[] h : repeatableHabits) {
            int value = loadCounter(today + ":" + h[0]);
            counters.put(h[0], value);
            counterViews.get(h[0]).setText(String.valueOf(value));
        }
        strangerComment.setText(prefs.getString(today + ":stranger_comment", ""));
        courageComment.setText(prefs.getString(today + ":courage_comment", ""));
        boardGameComment.setText(prefs.getString(today + ":board_game_comment", ""));
        sportsComment.setText(prefs.getString(today + ":sports_comment", ""));
        birthdayComment.setText(prefs.getString(today + ":birthday_comment", ""));
        String savedScriptUrl = prefs.getString("script_url", DEFAULT_SCRIPT_URL);
        scriptUrl.setText(savedScriptUrl.trim().isEmpty() ? DEFAULT_SCRIPT_URL : savedScriptUrl);
        loadingState = false;
        updateReadingSummary();
    }

    private void recordRecurringCompletion(String key, boolean completed) {
        if (!completed) return;
        if (key.equals("contact_oma") || key.equals("contact_mama") || key.equals("contact_ambi") || key.equals("shaved")) {
            prefs.edit().putLong("last_done:" + key, System.currentTimeMillis()).apply();
        }
    }

    private int loadCounter(String key) {
        try {
            return prefs.getInt(key, 0);
        } catch (ClassCastException ex) {
            return prefs.getBoolean(key, false) ? 1 : 0;
        }
    }

    private void saveState() {
        SharedPreferences.Editor e = prefs.edit();
        for (String[] h : habits) e.putBoolean(today + ":" + h[0], boxes.get(h[0]).isChecked());
        for (String[] h : repeatableHabits) e.putInt(today + ":" + h[0], counters.get(h[0]));
        e.putString(today + ":stranger_comment", strangerComment.getText().toString());
        e.putString(today + ":courage_comment", courageComment.getText().toString());
        e.putString(today + ":board_game_comment", boardGameComment.getText().toString());
        e.putString(today + ":sports_comment", sportsComment.getText().toString());
        e.putString(today + ":birthday_comment", birthdayComment.getText().toString());
        e.putString("script_url", scriptUrl.getText().toString().trim());
        e.apply();
    }

    private void updateSummary() {
        int done = 0; for (CheckBox cb : boxes.values()) if (cb.isChecked()) done++;
        for (int value : counters.values()) if (value > 0) done++;
        streakSummary.setText(done + "/" + (boxes.size() + counters.size()) + " habits done today");
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
        if (requestCode == REQ_BOOK_PHOTO) {
            if (resultCode == RESULT_OK && pendingBookPhoto != null) identifyBook(pendingBookPhoto);
            else discardPendingBookPhoto();
            return;
        }
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

    private void captureFinishedBook() {
        try {
            File dir = new File(getFilesDir(), "finished_books");
            if (!dir.exists() && !dir.mkdirs()) throw new Exception("Could not create photo folder");
            pendingBookPhoto = new File(dir, "book_" + System.currentTimeMillis() + ".jpg");
            Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".files", pendingBookPhoto);
            Intent camera = new Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE);
            camera.putExtra(android.provider.MediaStore.EXTRA_OUTPUT, uri);
            camera.setClipData(ClipData.newRawUri("finished book", uri));
            camera.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivityForResult(camera, REQ_BOOK_PHOTO);
        } catch (Exception ex) {
            pendingBookPhoto = null;
            toast("Could not open the camera: " + ex.getMessage());
        }
    }

    private void identifyBook(File photo) {
        status.setText("Reading the cover…");
        try {
            InputImage image = InputImage.fromFilePath(this, Uri.fromFile(photo));
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).process(image)
                    .addOnSuccessListener(result -> {
                        String text = result.getText().trim();
                        if (text.isEmpty()) showBookConfirmation("", "", 0, "");
                        else searchOpenLibrary(text);
                    })
                    .addOnFailureListener(ex -> {
                        status.setText("I couldn't read the cover. You can enter it manually.");
                        showBookConfirmation("", "", 0, "");
                    });
        } catch (Exception ex) {
            status.setText("I couldn't read the photo. You can enter the book manually.");
            showBookConfirmation("", "", 0, "");
        }
    }

    private void searchOpenLibrary(String coverText) {
        status.setText("Looking up the book in Open Library…");
        new Thread(() -> {
            try {
                String compact = coverText.replace('\n', ' ').replaceAll("\\s+", " ").trim();
                if (compact.length() > 180) compact = compact.substring(0, 180);
                String endpoint = "https://openlibrary.org/search.json?q=" + URLEncoder.encode(compact, "UTF-8")
                        + "&fields=key,title,author_name,number_of_pages_median&limit=1";
                JSONObject root = new JSONObject(getJson(endpoint));
                JSONArray docs = root.optJSONArray("docs");
                if (docs == null || docs.length() == 0) throw new Exception("No match");
                JSONObject book = docs.getJSONObject(0);
                String title = book.optString("title", "");
                JSONArray authors = book.optJSONArray("author_name");
                String author = authors != null && authors.length() > 0 ? authors.optString(0) : "";
                int pages = book.optInt("number_of_pages_median", 0);
                String key = book.optString("key", "");
                runOnUiThread(() -> showBookConfirmation(title, author, pages, key));
            } catch (Exception ex) {
                String[] lines = coverText.split("\\n");
                String guess = lines.length > 0 ? lines[0].trim() : "";
                runOnUiThread(() -> {
                    status.setText("No confident match found. Check the title before saving.");
                    showBookConfirmation(guess, "", 0, "");
                });
            }
        }).start();
    }

    private void showBookConfirmation(String title, String author, int pages, String openLibraryKey) {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL); form.setPadding(40, 8, 40, 0);
        EditText titleInput = addDialogField(form, "Title", title, InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        EditText authorInput = addDialogField(form, "Author", author, InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        EditText pagesInput = addDialogField(form, "Pages (optional)", pages > 0 ? String.valueOf(pages) : "", InputType.TYPE_CLASS_NUMBER);
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("Is this the book?").setView(form)
                .setPositiveButton("Save as finished", null)
                .setNegativeButton("Cancel", (d, which) -> discardPendingBookPhoto())
                .setOnCancelListener(d -> discardPendingBookPhoto()).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String finalTitle = titleInput.getText().toString().trim();
            if (finalTitle.isEmpty()) { titleInput.setError("Add a title"); return; }
            int finalPages = 0;
            try { finalPages = Integer.parseInt(pagesInput.getText().toString().trim()); } catch (Exception ignored) {}
            saveFinishedBook(finalTitle, authorInput.getText().toString().trim(), finalPages, openLibraryKey);
            dialog.dismiss();
        }));
        dialog.show();
    }

    private EditText addDialogField(LinearLayout form, String hint, String value, int inputType) {
        EditText field = new EditText(this); field.setHint(hint); field.setText(value); field.setInputType(inputType);
        form.addView(field); return field;
    }

    private void saveFinishedBook(String title, String author, int pages, String openLibraryKey) {
        try {
            JSONArray books = new JSONArray(prefs.getString("finished_books", "[]"));
            JSONObject book = new JSONObject();
            book.put("title", title); book.put("author", author); book.put("pages", pages);
            book.put("finishedDate", today); book.put("openLibraryKey", openLibraryKey);
            book.put("photoPath", pendingBookPhoto == null ? "" : pendingBookPhoto.getAbsolutePath());
            books.put(book);
            prefs.edit().putString("finished_books", books.toString()).apply();
            pendingBookPhoto = null;
            updateReadingSummary();
            status.setText("Saved “" + title + "” as finished.");
        } catch (Exception ex) { toast("Could not save book: " + ex.getMessage()); }
    }

    private void updateReadingSummary() {
        if (readingSummary == null) return;
        try {
            JSONArray books = new JSONArray(prefs.getString("finished_books", "[]"));
            int pages = 0; String recent = "";
            for (int i = 0; i < books.length(); i++) pages += books.optJSONObject(i).optInt("pages", 0);
            if (books.length() > 0) {
                JSONObject last = books.optJSONObject(books.length() - 1);
                recent = "\nLatest: " + last.optString("title") + (last.optString("author").isEmpty() ? "" : " — " + last.optString("author"));
                String path = last.optString("photoPath");
                if (!path.isEmpty() && new File(path).exists()) showSampledBookPhoto(path);
            }
            readingSummary.setText(books.length() + " books finished" + (pages > 0 ? " · " + pages + " pages" : "") + recent);
        } catch (Exception ex) { readingSummary.setText("0 books finished"); }
    }

    private void showSampledBookPhoto(String path) {
        BitmapFactory.Options bounds = new BitmapFactory.Options(); bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(path, bounds);
        int sample = 1;
        while (bounds.outWidth / sample > 1200 || bounds.outHeight / sample > 1200) sample *= 2;
        BitmapFactory.Options options = new BitmapFactory.Options(); options.inSampleSize = sample;
        latestBookPhoto.setImageBitmap(BitmapFactory.decodeFile(path, options));
    }

    private String getJson(String target) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(target).openConnection();
        c.setConnectTimeout(15000); c.setReadTimeout(15000);
        c.setRequestProperty("User-Agent", "HabitsTracker/1.0");
        try (InputStream in = c.getInputStream(); Scanner sc = new Scanner(in, "UTF-8").useDelimiter("\\A")) {
            return sc.hasNext() ? sc.next() : "{}";
        }
    }

    private void discardPendingBookPhoto() {
        if (pendingBookPhoto != null && pendingBookPhoto.exists()) pendingBookPhoto.delete();
        pendingBookPhoto = null;
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
        for (String[] h : repeatableHabits) { if (i++ > 0) sb.append(','); sb.append('\"').append(h[0]).append("\":").append(counters.get(h[0])); }
        sb.append("},\"stranger_comment\":\"").append(esc(strangerComment.getText().toString())).append("\",");
        sb.append("\"courage_comment\":\"").append(esc(courageComment.getText().toString())).append("\",");
        sb.append("\"board_game_comment\":\"").append(esc(boardGameComment.getText().toString())).append("\",");
        sb.append("\"sports_comment\":\"").append(esc(sportsComment.getText().toString())).append("\",");
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
        } else requestCommunicationPermissionsIfNeeded();
    }

    private void requestCommunicationPermissionsIfNeeded() {
        if (Build.VERSION.SDK_INT >= 23) {
            ArrayList<String> missing = new ArrayList<>();
            if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.READ_CONTACTS);
            if (checkSelfPermission(Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.READ_CALL_LOG);
            if (checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.READ_SMS);
            if (!missing.isEmpty()) requestPermissions(missing.toArray(new String[0]), REQ_COMMUNICATION_HISTORY);
            else CommunicationTracker.scan(this);
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_NOTIFICATIONS) requestCommunicationPermissionsIfNeeded();
        if (requestCode == REQ_COMMUNICATION_HISTORY) CommunicationTracker.scan(this);
    }

    private void scheduleReminders() {
        ReminderReceiver.scheduleAll(this);
        status.setText("Daily reminders scheduled for 10:00, 17:30, and 21:00.");
    }
}
