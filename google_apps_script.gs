const SPREADSHEET_ID = '1wm2F_TyIyqgwMdyK1z63AqZDnAhXlGZUeYkMEBD5iQo';

const HEADERS = [
  'timestamp','date','person','reading','eat_before_19','up_before_8','phone_off_22','pushups_10',
  'stranger_conversation','got_her_number','call_close_one','birthday_message_sent','birthday_called_instead',
  'cleaned_kitchen','cleaned_table','cleaned_floor','stranger_comment','birthday_comment','housework','stretching',
  'walking','journaling','courage','courage_comment','board_game','board_game_comment','sports','sports_comment',
  'contact_oma','contact_mama','contact_ambi','no_porn','shaved','lights_off_2245','close_one_comment',
  'birthday_done','uncle_exercise','uncle_call_meet_loved_one','uncle_exercise_comment','oleovit_allergy',
  'delayed_gratification_bored'
];

const HABIT_KEYS = [
  'reading','eat_before_19','up_before_8','phone_off_22','pushups_10','stranger_conversation','got_her_number',
  'call_close_one','birthday_message_sent','birthday_called_instead','cleaned_kitchen','cleaned_table','cleaned_floor',
  'housework','stretching','walking','journaling','courage','board_game','sports','contact_oma','contact_mama',
  'contact_ambi','no_porn','shaved','lights_off_2245','uncle_exercise','uncle_call_meet_loved_one',
  'oleovit_allergy','delayed_gratification_bored'
];

const COMMENT_KEYS = [
  'stranger_comment','birthday_comment','courage_comment','board_game_comment','sports_comment',
  'close_one_comment','uncle_exercise_comment'
];

function doPost(e) {
  try {
    const payload = JSON.parse((e.postData && e.postData.contents) || '{}');
    if (payload.action === 'saveDay') return json(saveDay(payload));
    if (payload.action === 'getDay') return json(getDay(payload.date, payload.person));
    if (payload.action === 'saveTasks') return json(saveTasks(payload.person, payload.tasks));
    if (payload.action === 'getTasks') return json(getTasks(payload.person));
    if (payload.action === 'getBirthdays') return json(getBirthdays(payload.date));
    return json({ ok: false, error: 'Unknown action' });
  } catch (error) {
    return json({ ok: false, error: String(error && error.message || error) });
  }
}

function saveTasks(person, tasks) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sheet = getOrCreateTaskSheet_();
    const who = person || 'Felix';
    const row = findPersonRow_(sheet, who);
    const values = [new Date(), who, JSON.stringify(tasks || [])];
    if (row) sheet.getRange(row, 1, 1, values.length).setValues([values]);
    else sheet.appendRow(values);
    return { ok: true, updated: Boolean(row) };
  } finally {
    lock.releaseLock();
  }
}

function getTasks(person) {
  const sheet = getOrCreateTaskSheet_();
  const who = person || 'Felix';
  const row = findPersonRow_(sheet, who);
  if (!row) return { ok: true, found: false, person: who, tasks: [] };
  let tasks = [];
  try { tasks = JSON.parse(sheet.getRange(row, 3).getValue() || '[]'); } catch (_) {}
  return { ok: true, found: true, person: who, tasks: tasks };
}

function findPersonRow_(sheet, person) {
  if (sheet.getLastRow() < 2) return 0;
  const people = sheet.getRange(2, 2, sheet.getLastRow() - 1, 1).getDisplayValues();
  for (let i = people.length - 1; i >= 0; i--) if (people[i][0] === String(person)) return i + 2;
  return 0;
}

function saveDay(payload) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sheet = getOrCreateSheet_();
    const h = payload.habits || {};
    const values = HEADERS.map(header => {
      if (header === 'timestamp') return new Date();
      if (header === 'date') return payload.date || '';
      if (header === 'person') return payload.person || 'Felix';
      if (HABIT_KEYS.includes(header)) return h[header] ?? false;
      if (COMMENT_KEYS.includes(header)) return payload[header] || '';
      if (header === 'birthday_done') return payload.birthday_done || false;
      return '';
    });
    const row = findDayRow_(sheet, payload.date, payload.person || 'Felix');
    if (row) sheet.getRange(row, 1, 1, HEADERS.length).setValues([values]);
    else sheet.appendRow(values);
    return { ok: true, updated: Boolean(row) };
  } finally {
    lock.releaseLock();
  }
}

function getDay(date, person) {
  const sheet = getOrCreateSheet_();
  const row = findDayRow_(sheet, date, person || 'Felix');
  if (!row) return { ok: true, found: false, date: date, person: person || 'Felix' };
  const values = sheet.getRange(row, 1, 1, HEADERS.length).getValues()[0];
  const data = { ok: true, found: true, habits: {} };
  HEADERS.forEach((header, index) => {
    if (HABIT_KEYS.includes(header)) data.habits[header] = values[index];
    else if (header !== 'timestamp') data[header] = values[index];
  });
  return data;
}

function findDayRow_(sheet, date, person) {
  if (!date || sheet.getLastRow() < 2) return 0;
  const rows = sheet.getRange(2, 2, sheet.getLastRow() - 1, 2).getDisplayValues();
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i][0] === String(date) && rows[i][1] === String(person)) return i + 2;
  }
  return 0;
}

function getBirthdays(dateString) {
  const date = dateString ? new Date(dateString + 'T12:00:00') : new Date();
  const calendars = CalendarApp.getAllCalendars();
  const results = [];
  calendars.forEach(cal => {
    const name = cal.getName();
    const maybeBirthdayCalendar = /birthday|geburtstag/i.test(name);
    cal.getEventsForDay(date).forEach(ev => {
      const title = ev.getTitle();
      if (maybeBirthdayCalendar || /birthday|geburtstag/i.test(title)) results.push({ calendar: name, title: title });
    });
  });
  return {
    ok: true,
    date: dateString,
    birthdays: results,
    message: results.length ? results.map(r => r.title).join('\n') : 'No birthdays found today.'
  };
}

function getOrCreateSheet_() {
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  let sheet = ss.getSheetByName('daily_log');
  if (!sheet) sheet = ss.insertSheet('daily_log');
  if (sheet.getLastRow() === 0) sheet.appendRow(HEADERS);
  else if (sheet.getLastColumn() < HEADERS.length) sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
  return sheet;
}

function getOrCreateTaskSheet_() {
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  let sheet = ss.getSheetByName('delegated_tasks');
  if (!sheet) sheet = ss.insertSheet('delegated_tasks');
  if (sheet.getLastRow() === 0) sheet.appendRow(['updated_at', 'person', 'tasks_json']);
  return sheet;
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
