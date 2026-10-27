-- =====================================================================
-- Portfolio 4 | 01_export_to_ndjson.sql
-- Transforms the relational data of The Homes into document-shaped JSON
-- (one JSON document per line, "NDJSON") ready for mongoimport.
--
-- Run from the portfolio-4-nosql folder:
--   mkdir -p data
--   psql -U postgres -d the_homes -f sql/01_export_to_ndjson.sql
--
-- Produces (in ./data):
--   hotels.ndjson           5 documents   (hotel + embedded rooms and services)
--   guest_profiles.ndjson   50,000        (profile + flexible preferences + stay summary)
--   reviews.ndjson          about 50,000  (guest reviews, flexible rating fields)
--   activity_events.ndjson  about 145,000 (event log with a different payload per type)
--
-- Nothing in the relational database is changed. The temporary tables
-- disappear when the session ends. Dates are written as MongoDB extended JSON
-- ({"$date": ...}) so they are imported as real Date values.
-- =====================================================================
\set ON_ERROR_STOP on
\timing on
SET client_encoding = 'UTF8';
SELECT setseed(0.42);

-- Helper: timestamp/date -> MongoDB extended JSON date
CREATE OR REPLACE FUNCTION pg_temp.mdate(ts timestamp) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('$date', to_char(ts, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
$$;

-- =====================================================================
-- 1. HOTELS: one document per hotel, rooms and services EMBEDDED
--    (bounded arrays that are always read together with the hotel)
-- =====================================================================
CREATE TEMP TABLE nosql_hotels AS
SELECT h.hotel_id AS id,
       jsonb_build_object(
         '_id', h.hotel_id,
         'name', h.name, 'city', h.city, 'country', h.country, 'address', h.address,
         'contact', jsonb_build_object('phone', h.phone, 'email', h.email),
         'star_rating', h.star_rating,
         'rooms', (SELECT jsonb_agg(jsonb_build_object(
                         'room_id', r.room_id, 'number', r.room_number, 'floor', r.floor,
                         'type', rt.type_name, 'max_occupancy', rt.max_occupancy,
                         'amenities', (SELECT coalesce(jsonb_agg(a.amenity_name ORDER BY a.amenity_id), '[]'::jsonb)
                                       FROM room_type_amenity rta JOIN amenity a ON a.amenity_id = rta.amenity_id
                                       WHERE rta.room_type_id = rt.room_type_id))
                         ORDER BY r.room_id)
                   FROM room r JOIN room_type rt ON rt.room_type_id = r.room_type_id
                   WHERE r.hotel_id = h.hotel_id),
         'services', (SELECT jsonb_agg(jsonb_build_object('name', s.service_name, 'unit_price', s.unit_price)
                                       ORDER BY s.service_id)
                      FROM service s WHERE s.hotel_id = h.hotel_id)
       ) AS doc
FROM hotel h;

-- =====================================================================
-- 2. GUEST PROFILES: one document per guest
--    Flexible, sparse preferences + a pre-computed stay summary
--    + the five most recent stays embedded (read the whole profile in one lookup)
-- =====================================================================
CREATE TEMP TABLE tmp_stats AS
SELECT b.guest_id,
       count(*) FILTER (WHERE b.status = 'completed')                              AS stays,
       coalesce(sum(b.check_out_date - b.check_in_date) FILTER (WHERE b.status = 'completed'), 0) AS nights,
       max(b.check_out_date) FILTER (WHERE b.status = 'completed')                 AS last_stay,
       array_agg(DISTINCT b.hotel_id) FILTER (WHERE b.status = 'completed')        AS hotels
FROM booking b GROUP BY b.guest_id;

CREATE TEMP TABLE tmp_spend AS
SELECT b.guest_id, sum(i.total_amount) AS spend
FROM invoice i JOIN booking b ON b.booking_id = i.booking_id
WHERE i.status = 'paid' GROUP BY b.guest_id;

CREATE TEMP TABLE tmp_recent AS
SELECT guest_id,
       jsonb_agg(jsonb_build_object('booking_id', booking_id, 'hotel_id', hotel_id, 'hotel', hotel,
                                    'check_in', pg_temp.mdate(check_in_date),
                                    'check_out', pg_temp.mdate(check_out_date),
                                    'room_type', room_type, 'status', status)
                 ORDER BY check_in_date DESC) AS stays
FROM (SELECT b.guest_id, b.booking_id, b.hotel_id, h.name AS hotel, b.check_in_date, b.check_out_date,
             rt.type_name AS room_type, b.status,
             row_number() OVER (PARTITION BY b.guest_id ORDER BY b.check_in_date DESC) AS rn
      FROM booking b
      JOIN hotel h        ON h.hotel_id = b.hotel_id
      JOIN booking_room br ON br.booking_id = b.booking_id
      JOIN room r         ON r.room_id = br.room_id
      JOIN room_type rt   ON rt.room_type_id = r.room_type_id
      WHERE b.status IN ('completed', 'checked_in')) t
WHERE rn <= 5
GROUP BY guest_id;

-- Preferences are deliberately SPARSE: each guest only has the fields they actually gave
CREATE TEMP TABLE tmp_prefs AS
SELECT guest_id,
       jsonb_strip_nulls(jsonb_build_object(
         'bed',          CASE WHEN random() < 0.60 THEN (ARRAY['king','queen','twin'])[1 + floor(random()*3)::int] END,
         'floor',        CASE WHEN random() < 0.35 THEN (ARRAY['high','low','quiet wing'])[1 + floor(random()*3)::int] END,
         'pillow',       CASE WHEN random() < 0.25 THEN (ARRAY['firm','soft','hypoallergenic'])[1 + floor(random()*3)::int] END,
         'dining',       CASE WHEN random() < 0.30 THEN jsonb_build_array((ARRAY['vegetarian','halal','no pork','gluten free','no shellfish'])[1 + floor(random()*5)::int]) END,
         'late_checkout',CASE WHEN random() < 0.20 THEN true END,
         'languages',    CASE WHEN random() < 0.40 THEN jsonb_build_array((ARRAY['English','French','Hausa','Yoruba','Igbo','Swahili'])[1 + floor(random()*6)::int]) END,
         'newsletter',   random() < 0.50
       )) AS prefs
FROM guest;

CREATE TEMP TABLE nosql_guest_profiles AS
SELECT g.guest_id AS id,
       jsonb_strip_nulls(jsonb_build_object(
         '_id', g.guest_id,
         'name', jsonb_build_object('first', g.first_name, 'last', g.last_name),
         'email', g.email, 'phone', g.phone, 'nationality', g.nationality,
         'registered_at', pg_temp.mdate(g.registered_at),
         'loyalty', CASE WHEN la.loyalty_id IS NOT NULL
                         THEN jsonb_build_object('tier', la.tier, 'points', la.points_balance) END,
         'preferences', p.prefs,
         'stay_summary', jsonb_build_object(
              'completed_stays', coalesce(s.stays, 0),
              'nights', coalesce(s.nights, 0),
              'total_spend', round(coalesce(sp.spend, 0), 2),
              'last_stay', CASE WHEN s.last_stay IS NOT NULL THEN pg_temp.mdate(s.last_stay) END,
              'hotels_visited', to_jsonb(coalesce(s.hotels, '{}'::int[]))),
         'recent_stays', coalesce(r.stays, '[]'::jsonb)
       )) AS doc
FROM guest g
LEFT JOIN loyalty_account la ON la.guest_id = g.guest_id
LEFT JOIN tmp_prefs p        ON p.guest_id  = g.guest_id
LEFT JOIN tmp_stats s        ON s.guest_id  = g.guest_id
LEFT JOIN tmp_spend sp       ON sp.guest_id = g.guest_id
LEFT JOIN tmp_recent r       ON r.guest_id  = g.guest_id;

-- =====================================================================
-- 3. REVIEWS: about a quarter of completed stays leave a review.
--    Rating categories and optional fields differ between reviews.
-- =====================================================================
CREATE TEMP TABLE tag_sentence(tag text, positive boolean, sentence text);
INSERT INTO tag_sentence VALUES
 ('breakfast', true,  'Breakfast was fresh and plentiful.'),
 ('breakfast', false, 'Breakfast was cold and the queue was long.'),
 ('cleanliness', true,  'The room was spotless.'),
 ('cleanliness', false, 'The bathroom was not properly cleaned.'),
 ('staff', true,  'The staff were warm and very helpful.'),
 ('staff', false, 'Staff seemed uninterested and slow to respond.'),
 ('location', true,  'Great location, close to everything we needed.'),
 ('location', false, 'The location was inconvenient and hard to reach.'),
 ('noise', true,  'It was wonderfully quiet at night.'),
 ('noise', false, 'Noise from the corridor and street kept us awake.'),
 ('wifi', true,  'WiFi was fast and reliable.'),
 ('wifi', false, 'The WiFi kept dropping, which made working difficult.'),
 ('value', true,  'Good value for the price.'),
 ('value', false, 'Too expensive for what was offered.'),
 ('pool', true,  'The pool area was lovely.'),
 ('pool', false, 'The pool was closed during our stay.'),
 ('parking', true,  'Parking was easy and secure.'),
 ('parking', false, 'Parking was limited and disorganised.'),
 ('air conditioning', true,  'The air conditioning worked perfectly.'),
 ('air conditioning', false, 'The air conditioning was weak and noisy.'),
 ('check-in', true,  'Check-in was quick and friendly.'),
 ('check-in', false, 'Check-in took far too long.'),
 ('spa', true,  'The spa treatments were excellent.'),
 ('spa', false, 'The spa was overbooked and disappointing.');

CREATE TEMP TABLE tmp_rev_base AS
SELECT b.booking_id, b.guest_id, b.hotel_id, h.name AS hotel_name, rt.type_name AS room_type,
       b.check_in_date, b.check_out_date,
       g.first_name || ' ' || left(g.last_name, 1) || '.' AS guest_display,
       least(0.999, greatest(0, random() + CASE b.hotel_id WHEN 2 THEN 0.08 WHEN 3 THEN -0.10 ELSE 0 END)) AS u,
       (ARRAY['breakfast','cleanliness','staff','location','noise','wifi','value','pool','parking','air conditioning','check-in','spa'])[1 + floor(random()*12)::int] AS tag1,
       (ARRAY['breakfast','cleanliness','staff','location','noise','wifi','value','pool','parking','air conditioning','check-in','spa'])[1 + floor(random()*12)::int] AS tag2,
       floor(random()*6)::int AS days_after, random() AS u_hour,
       random() AS u_food, random() AS u_resp, random() AS u_trip, random() AS u_votes,
       random() AS u_s1, random() AS u_s2, random() AS u_s3, random() AS u_s4, random() AS u_s5, random() AS u_s6
FROM booking b
JOIN hotel h         ON h.hotel_id = b.hotel_id
JOIN guest g         ON g.guest_id = b.guest_id
JOIN booking_room br ON br.booking_id = b.booking_id
JOIN room r          ON r.room_id = br.room_id
JOIN room_type rt    ON rt.room_type_id = r.room_type_id
WHERE b.status = 'completed' AND random() < 0.25;

CREATE TEMP TABLE tmp_rev AS
SELECT x.*,
       CASE WHEN u < 0.05 THEN 1 WHEN u < 0.12 THEN 2 WHEN u < 0.25 THEN 3 WHEN u < 0.55 THEN 4 ELSE 5 END AS overall
FROM tmp_rev_base x;

CREATE TEMP TABLE nosql_reviews AS
SELECT t.booking_id AS id,
       jsonb_strip_nulls(jsonb_build_object(
         '_id', t.booking_id, 'booking_id', t.booking_id,
         'hotel_id', t.hotel_id, 'hotel', t.hotel_name,
         'guest_id', t.guest_id, 'guest_display', t.guest_display,
         'room_type', t.room_type,
         'stay', jsonb_build_object('check_in', pg_temp.mdate(t.check_in_date),
                                    'check_out', pg_temp.mdate(t.check_out_date),
                                    'nights', t.check_out_date - t.check_in_date),
         'posted_at', pg_temp.mdate(t.check_out_date + t.days_after + (t.u_hour * interval '12 hours')::interval + interval '8 hours'),
         'rating', jsonb_strip_nulls(jsonb_build_object(
              'overall', t.overall,
              'cleanliness', least(5, greatest(1, t.overall + (floor(t.u_s1*3)::int - 1))),
              'service',     least(5, greatest(1, t.overall + (floor(t.u_s2*3)::int - 1))),
              'location',    least(5, greatest(1, t.overall + (floor(t.u_s3*3)::int - 1))),
              'value',       least(5, greatest(1, t.overall + (floor(t.u_s4*3)::int - 1))),
              'food',        CASE WHEN t.u_food < 0.40 THEN least(5, greatest(1, t.overall + (floor(t.u_s5*3)::int - 1))) END)),
         'title', (CASE WHEN t.overall >= 4 THEN (ARRAY['Wonderful stay','Highly recommended','Will be back','Excellent hotel'])[1 + floor(t.u_s6*4)::int]
                        WHEN t.overall = 3 THEN (ARRAY['Decent but room for improvement','Average stay','Mixed feelings'])[1 + floor(t.u_s6*3)::int]
                        ELSE (ARRAY['Disappointing','Not as expected','Would not return'])[1 + floor(t.u_s6*3)::int] END),
         'comment', CASE WHEN t.tag1 = t.tag2 THEN s1.sentence ELSE s1.sentence || ' ' || s2.sentence END,
         'tags', CASE WHEN t.tag1 = t.tag2 THEN jsonb_build_array(t.tag1) ELSE jsonb_build_array(t.tag1, t.tag2) END,
         'language', 'en',
         'trip_type', CASE WHEN t.u_trip < 0.5 THEN (ARRAY['business','leisure','family','couple'])[1 + floor(t.u_trip*8)::int] END,
         'would_recommend', t.overall >= 4,
         'helpful_votes', floor(t.u_votes * t.u_votes * 25)::int,
         'hotel_response', CASE WHEN t.u_resp < CASE WHEN t.overall <= 2 THEN 0.8 ELSE 0.25 END
              THEN jsonb_build_object('responded_at', pg_temp.mdate(t.check_out_date + t.days_after + 2 + interval '10 hours'),
                                      'by', 'Guest Relations',
                                      'text', CASE WHEN t.overall >= 4 THEN 'Thank you for staying with us. We look forward to welcoming you back.'
                                                   ELSE 'We are sorry your stay fell short. Please contact us so we can make it right.' END)
         END
       )) AS doc
FROM tmp_rev t
JOIN tag_sentence s1 ON s1.tag = t.tag1 AND s1.positive = (t.overall >= 3)
JOIN tag_sentence s2 ON s2.tag = t.tag2 AND s2.positive = (t.overall >= 4);

-- =====================================================================
-- 4. ACTIVITY EVENTS: an event log whose payload differs by event type
-- =====================================================================
CREATE TEMP TABLE nosql_events AS
SELECT row_number() OVER ()::int AS id, doc FROM (
    -- booking_created
    SELECT jsonb_build_object('ts', pg_temp.mdate(b.booked_at), 'hotel_id', b.hotel_id,
             'type', 'booking_created', 'source', 'pms',
             'payload', jsonb_build_object('booking_id', b.booking_id, 'channel', bs.source_name,
                                           'nights', b.check_out_date - b.check_in_date, 'guests', b.num_guests)) AS doc
    FROM booking b JOIN booking_source bs ON bs.source_id = b.source_id WHERE random() < 0.20
  UNION ALL
    -- check_in
    SELECT jsonb_build_object('ts', pg_temp.mdate(sr.checked_in_at), 'hotel_id', b.hotel_id,
             'type', 'check_in', 'source', 'pms',
             'payload', jsonb_build_object('booking_id', b.booking_id, 'room_id', br.room_id, 'staff_id', sr.checkin_by))
    FROM stay_record sr
    JOIN booking_room br ON br.booking_room_id = sr.booking_room_id
    JOIN booking b       ON b.booking_id = br.booking_id
    WHERE random() < 0.20
  UNION ALL
    -- door_unlock (IoT)
    SELECT jsonb_build_object('ts', pg_temp.mdate(now()::timestamp - random() * interval '120 days'),
             'hotel_id', r.hotel_id, 'type', 'door_unlock', 'source', 'iot',
             'payload', jsonb_build_object('room_id', r.room_id,
                                           'method', (ARRAY['keycard','mobile','keycard','master'])[1 + floor(random()*4)::int]))
    FROM (SELECT 1 + floor(random()*600)::int AS room_id FROM generate_series(1, 40000)) g
    JOIN room r ON r.room_id = g.room_id
  UNION ALL
    -- thermostat_set (IoT)
    SELECT jsonb_build_object('ts', pg_temp.mdate(now()::timestamp - random() * interval '120 days'),
             'hotel_id', r.hotel_id, 'type', 'thermostat_set', 'source', 'iot',
             'payload', jsonb_build_object('room_id', r.room_id, 'celsius', 18 + floor(random()*9)::int))
    FROM (SELECT 1 + floor(random()*600)::int AS room_id FROM generate_series(1, 20000)) g
    JOIN room r ON r.room_id = g.room_id
  UNION ALL
    -- noise_alert (IoT, rare)
    SELECT jsonb_build_object('ts', pg_temp.mdate(now()::timestamp - random() * interval '120 days'),
             'hotel_id', r.hotel_id, 'type', 'noise_alert', 'source', 'iot',
             'payload', jsonb_build_object('room_id', r.room_id, 'decibels', 70 + floor(random()*25)::int,
                                           'resolved', random() < 0.9))
    FROM (SELECT 1 + floor(random()*600)::int AS room_id FROM generate_series(1, 3000)) g
    JOIN room r ON r.room_id = g.room_id
) e;

-- =====================================================================
-- 5. Write the files (one JSON document per line)
--    QUOTE/DELIMITER are control characters so JSON text is written untouched
-- =====================================================================
\copy (SELECT doc::text FROM nosql_hotels ORDER BY id) TO 'data/hotels.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')
\copy (SELECT doc::text FROM nosql_guest_profiles ORDER BY id) TO 'data/guest_profiles.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')
\copy (SELECT doc::text FROM nosql_reviews ORDER BY id) TO 'data/reviews.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')
\copy (SELECT doc::text FROM nosql_events ORDER BY id) TO 'data/activity_events.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

SELECT 'hotels' AS file, count(*) AS documents FROM nosql_hotels
UNION ALL SELECT 'guest_profiles', count(*) FROM nosql_guest_profiles
UNION ALL SELECT 'reviews', count(*) FROM nosql_reviews
UNION ALL SELECT 'activity_events', count(*) FROM nosql_events;
