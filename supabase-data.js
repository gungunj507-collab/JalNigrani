import { supabase } from './supabase.js';

const tables = { profiles: 'profiles', devices: 'water_devices', readings: 'water_readings', alerts: 'alerts' };
const number = (...values) => Number(values.find(value => value !== undefined && value !== null && value !== '') || 0) || 0;
const text = (...values) => values.find(value => value !== undefined && value !== null && value !== '') || '';
const displayTime = value => value ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '-';
const date = row => text(row.recorded_at, row.detected_at, row.created_at, row.updated_at);
const isTestData = payload => payload?.is_test === true || payload?.source === 'demo' || payload?.source === 'test';

async function query(name, orderColumn = 'created_at') {
  const { data, error } = await supabase.from(name).select('*').order(orderColumn, { ascending: false }).limit(500);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data || [];
}
function makeReports(readings) {
  const now = new Date();
  return [['Today', new Date(now.getFullYear(), now.getMonth(), now.getDate())], ['This week', new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6)], ['This month', new Date(now.getFullYear(), now.getMonth(), 1)]].map(([period, since]) => {
    const readingRows = readings.filter(row => new Date(row.rawTime) >= since);
    const total = readingRows.reduce((sum, row) => sum + row.usageLitres, 0);
    const flow = readingRows.length ? readingRows.reduce((sum, row) => sum + row.flow, 0) / readingRows.length : 0;
    const availability = readingRows.length ? readingRows.reduce((sum, row) => sum + row.availability, 0) / readingRows.length : 0;
    return { period, water: `${Math.round(total).toLocaleString()} L`, flow: `${Math.round(flow)} L/min`, availability: readingRows.length ? `${Math.round(availability)}%` : '-', change: '-' };
  });
}

export async function loadWaterData() {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) throw new Error(userError?.message || 'Your session has expired. Please sign in again.');
  const [profileResult, readingRows, alertRows, deviceRows] = await Promise.all([
    supabase.from(tables.profiles).select('*').eq('id', user.id).maybeSingle(),
    query(tables.readings, 'recorded_at'), query(tables.alerts, 'detected_at'), query(tables.devices)
  ]);
  if (profileResult.error) throw new Error(`profiles: ${profileResult.error.message}`);
  const readings = readingRows.map(row => {
    const rawTime = date(row);
    return { id: text(row.id), rawTime, time: displayTime(rawTime), availability: number(row.availability), flow: number(row.flow_rate), usage: number(row.usage_percent), usageLitres: number(row.usage_litres), status: isTestData(row.sensor_payload) ? 'Test' : String(text(row.status, 'normal')).replace(/^./, value => value.toUpperCase()) };
  });
  const alerts = alertRows.map(row => ({ id: text(row.id), type: isTestData(row.metadata) ? `Test: ${text(row.type, 'Alert')}` : text(row.type, 'Alert'), detail: text(row.message, 'No details provided.'), priority: String(text(row.priority, 'medium')).replace(/^./, value => value.toUpperCase()), time: displayTime(date(row)), status: String(text(row.status, 'active')).replace(/^./, value => value.toUpperCase()) }));
  const devices = deviceRows.map(row => ({ id: text(row.id), name: text(row.name, 'Monitoring device'), status: String(text(row.status, 'unknown')).replace(/^./, value => value.toUpperCase()), zone: text(row.zone, row.location, '-') }));
  const latest = readings[0], chronological = [...readings].reverse();
  const today = new Date().toISOString().slice(0, 10);
  const dailyUsage = readings.filter(row => row.rawTime?.slice(0, 10) === today).reduce((sum, row) => sum + row.usageLitres, 0);
  const labels = chronological.slice(-12).map(row => row.rawTime ? new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit' }).format(new Date(row.rawTime)) : '-');
  const online = devices.filter(device => /online|active|connected|operational/i.test(device.status)).length;
  return { mode: 'Live data', sourceNote: 'Live data from Supabase', profile: profileResult.data, system: { availability: latest?.availability || 0, flowRate: latest?.flow || 0, dailyUsage, estimatedAvailable: 0, status: devices.length ? `${online}/${devices.length} online` : 'No devices' }, readings, alerts, devices, trends: { labels, availability: chronological.slice(-12).map(row => row.availability), flow: chronological.slice(-12).map(row => row.flow), weeklyAvailability: chronological.slice(-7).map(row => row.availability) }, activity: alerts.slice(0, 3).map(alert => ({ icon: '!', title: alert.type, text: alert.detail, time: alert.time })), reports: makeReports(readings) };
}

export async function markAlertResolved(alert) {
  if (!alert?.id) throw new Error('This alert has no id, so it cannot be updated.');
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) throw new Error(userError?.message || 'You must be signed in to resolve an alert.');
  const { error } = await supabase.from(tables.alerts).update({ status: 'resolved', resolved_at: new Date().toISOString(), resolved_by: user.id }).eq('id', alert.id);
  if (error) throw new Error(error.message);
}
