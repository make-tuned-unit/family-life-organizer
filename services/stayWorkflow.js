// One hosting workflow for native HTTP and Concierge. Calendar writes and the
// state transition commit together; retries cannot mint duplicate events.
function fail(status, message) { const e = new Error(message); e.status = status; throw e; }
async function requestStay({ db, userId, push }, stayId) {
  const stay = await db.getItineraryStayById(stayId);
  if (!stay) fail(404, 'Stay not found');
  const itinerary = await db.getItineraryById(stay.itinerary_id);
  if (!itinerary || itinerary.traveler_id !== userId) fail(403, 'Only the traveler can request a stay');
  if (!stay.host_user_id) fail(400, 'Choose an app member as host first');
  if (stay.status === 'requested') return { success: true };
  if (stay.status === 'confirmed') fail(409, 'This stay is already confirmed');
  await db.updateItineraryStay(stay.id, { status: 'requested' });
  if (push) push.pushToUser(db, stay.host_user_id, `${itinerary.traveler_name || 'Someone'} wants to stay with you`, `${stay.check_in} to ${stay.check_out}${stay.notes ? ' — ' + stay.notes : ''}`, { type: 'stay_request', ref_id: stay.id });
  return { success: true };
}
async function respondToStay({ db, userId, userName, push }, stayId, approved) {
  if (typeof approved !== 'boolean') fail(400, 'approved must be a boolean');
  let stay, itinerary;
  await db.transaction(async db => {
    stay = await db.getItineraryStayById(stayId);
    if (!stay) fail(404, 'Stay not found');
    if (stay.host_user_id !== userId) fail(403, 'Only the host can respond');
    if (stay.status !== 'requested') fail(409, 'This stay is not awaiting a response');
    itinerary = await db.getItineraryById(stay.itinerary_id);
    if (!itinerary) fail(404, 'Itinerary not found');
    if (approved) {
      const travelerGroupId = await db.getUserHouseholdId(itinerary.traveler_id);
      const hostGroupId = await db.getUserHouseholdId(userId);
      if (!travelerGroupId || !hostGroupId) fail(409, 'Both host and traveler need a household');
      const travelerEvent = await db.addAppointment({ title: `Staying at ${userName}'s`, appointment_date: stay.check_in, description: `${stay.check_in} to ${stay.check_out}${stay.location_name ? ' · ' + stay.location_name : ''}`, location: stay.address || stay.location_name || null, category: 'social', with_person: userName, group_id: travelerGroupId });
      const hostEvent = await db.addAppointment({ title: `${itinerary.traveler_name || 'Visitor'} visiting`, appointment_date: stay.check_in, description: `${stay.check_in} to ${stay.check_out}`, location: stay.address || stay.location_name || null, category: 'social', with_person: itinerary.traveler_name || 'Visitor', group_id: hostGroupId });
      await db.updateItineraryStay(stay.id, { status: 'confirmed', calendar_event_id: travelerEvent.id, host_calendar_event_id: hostEvent.id });
    } else await db.updateItineraryStay(stay.id, { status: 'declined' });
  });
  if (push && itinerary.traveler_id) push.pushToUser(db, itinerary.traveler_id,
    approved ? `${userName} confirmed your stay!` : `${userName} can't host ${stay.check_in} to ${stay.check_out}`,
    approved ? `${stay.check_in} to ${stay.check_out} is all set` : 'You may need to adjust your itinerary',
    { type: approved ? 'stay_confirmed' : 'stay_declined', ref_id: stay.id });
  return { success: true };
}
module.exports = { requestStay, respondToStay };
