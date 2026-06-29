const SPREADSHEET_ID = 'PASTE_YOUR_GOOGLE_SHEET_ID_HERE';

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
    'stranger_comment','birthday_comment'
  ]);
  const h = payload.habits || {};
  sheet.appendRow([
    new Date(), payload.date || '', h.reading || false, h.eat_before_19 || false, h.up_before_8 || false,
    h.phone_off_22 || false, h.pushups_10 || false, h.stranger_conversation || false, h.got_her_number || false,
    h.call_close_one || false, h.birthday_message_sent || false, h.birthday_called_instead || false,
    payload.stranger_comment || '', payload.birthday_comment || ''
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
  }
  return sh;
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
