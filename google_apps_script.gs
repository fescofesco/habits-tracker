const SPREADSHEET_ID = '1wm2F_TyIyqgwMdyK1z63AqZDnAhXlGZUeYkMEBD5iQo';

function doPost(e) {
  const payload = JSON.parse(e.postData.contents || '{}');
  if (payload.action === 'saveDay') return json(saveDay(payload));
  if (payload.action === 'getBirthdays') return json(getBirthdays(payload.date));
  return json({ ok: false, error: 'Unknown action' });
}

function saveDay(payload) {
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  const sheet = getOrCreateSheet_(ss, 'daily_log', [
    'timestamp','date','reading','eat_before_19','up_before_8','phone_off_22','pushups_10',
    'stranger_conversation','got_her_number','call_close_one','birthday_message_sent','birthday_called_instead',
    'cleaned_kitchen','cleaned_table','cleaned_floor',
    'stranger_comment','birthday_comment','housework','stretching','walking','journaling','courage','courage_comment',
    'board_game','board_game_comment','sports','sports_comment',
    'contact_oma','contact_mama','contact_ambi','no_porn','shaved','lights_off_2245',
    'close_one_comment','birthday_done','uncle_exercise','uncle_call_meet_loved_one'
  ]);
  const h = payload.habits || {};
  sheet.appendRow([
    new Date(), payload.date || '', h.reading || 0, h.eat_before_19 || false, h.up_before_8 || false,
    h.phone_off_22 || false, h.pushups_10 || 0, h.stranger_conversation || 0, h.got_her_number || 0,
    h.call_close_one || false, h.birthday_message_sent || false, h.birthday_called_instead || false,
    h.cleaned_kitchen || false, h.cleaned_table || false, h.cleaned_floor || false,
    payload.stranger_comment || '', payload.birthday_comment || '',
    h.housework || 0, h.stretching || 0, h.walking || 0, h.journaling || false, h.courage || false,
    payload.courage_comment || '', h.board_game || false, payload.board_game_comment || '',
    h.sports || false, payload.sports_comment || '',
    h.contact_oma || false, h.contact_mama || false, h.contact_ambi || false,
    h.no_porn || false, h.shaved || false, h.lights_off_2245 || false,
    payload.close_one_comment || '', payload.birthday_done || false,
    h.uncle_exercise || false, h.uncle_call_meet_loved_one || false
  ]);
  return { ok: true };
}

function getBirthdays(dateString) {
  const date = dateString ? new Date(dateString + 'T12:00:00') : new Date();
  const calendars = CalendarApp.getAllCalendars();
  const results = [];
  calendars.forEach(cal => {
    const name = cal.getName();
    const maybeBirthdayCalendar = /birthday|geburtstag/i.test(name);
    const events = cal.getEventsForDay(date);
    events.forEach(ev => {
      const title = ev.getTitle();
      if (maybeBirthdayCalendar || /birthday|geburtstag/i.test(title)) {
        results.push({ calendar: name, title: title });
      }
    });
  });
  if (results.length === 0) return { ok: true, date: dateString, birthdays: [], message: 'No birthdays found today.' };
  return { ok: true, date: dateString, birthdays: results, message: results.map(r => r.title).join('\n') };
}

function getOrCreateSheet_(ss, name, headers) {
  let sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.appendRow(headers);
  } else if (sh.getLastColumn() < headers.length) {
    sh.getRange(1, 1, 1, headers.length).setValues([headers]);
  }
  return sh;
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
