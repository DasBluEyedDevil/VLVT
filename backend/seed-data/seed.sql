-- NoBS Dating Test Database Seeding Script
-- This script creates realistic test users, profiles, matches, and messages
-- for comprehensive testing of the application

-- Clean existing test data (optional - uncomment to reset)
-- DELETE FROM messages WHERE match_id LIKE 'test_%';
-- DELETE FROM matches WHERE id LIKE 'test_%';
-- DELETE FROM blocks WHERE user_id LIKE 'google_test%' OR blocked_user_id LIKE 'google_test%';
-- DELETE FROM reports WHERE reporter_id LIKE 'google_test%' OR reported_user_id LIKE 'google_test%';
-- DELETE FROM profiles WHERE user_id LIKE 'google_test%';
-- DELETE FROM users WHERE id LIKE 'google_test%';

-- ============================================================================
-- TEST USERS
-- ============================================================================
-- Format: google_test[number] for easy identification
-- These simulate Google OAuth authenticated users

INSERT INTO users (id, provider, email, created_at, updated_at) VALUES
('google_test001', 'google', 'alex.chen@test.com', NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days'),
('google_test002', 'google', 'jordan.rivera@test.com', NOW() - INTERVAL '28 days', NOW() - INTERVAL '28 days'),
('google_test003', 'google', 'sam.patel@test.com', NOW() - INTERVAL '25 days', NOW() - INTERVAL '25 days'),
('google_test004', 'google', 'taylor.kim@test.com', NOW() - INTERVAL '22 days', NOW() - INTERVAL '22 days'),
('google_test005', 'google', 'morgan.santos@test.com', NOW() - INTERVAL '20 days', NOW() - INTERVAL '20 days'),
('google_test006', 'google', 'casey.nguyen@test.com', NOW() - INTERVAL '18 days', NOW() - INTERVAL '18 days'),
('google_test007', 'google', 'riley.anderson@test.com', NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days'),
('google_test008', 'google', 'avery.williams@test.com', NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days'),
('google_test009', 'google', 'drew.martinez@test.com', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days'),
('google_test010', 'google', 'charlie.lee@test.com', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days'),
('google_test011', 'google', 'jamie.brown@test.com', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days'),
('google_test012', 'google', 'quinn.davis@test.com', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),
('google_test013', 'google', 'reese.garcia@test.com', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days'),
('google_test014', 'google', 'skylar.wilson@test.com', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days'),
('google_test015', 'google', 'blake.moore@test.com', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
('google_test016', 'google', 'phoenix.taylor@test.com', NOW() - INTERVAL '1 days', NOW() - INTERVAL '1 days'),
('google_test017', 'google', 'sage.jackson@test.com', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),
('google_test018', 'google', 'dakota.white@test.com', NOW() - INTERVAL '6 hours', NOW() - INTERVAL '6 hours'),
('google_test019', 'google', 'river.harris@test.com', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours'),
('google_test020', 'google', 'ocean.clark@test.com', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- TEST PROFILES
-- ============================================================================
-- Diverse, realistic profiles with varied interests and bios

INSERT INTO profiles (user_id, name, age, bio, photos, interests, created_at, updated_at) VALUES
(
    'google_test001',
    'Alex Chen',
    28,
    'Software engineer by day, amateur chef by night. Love exploring new restaurants and trying to recreate the dishes at home. Always up for spontaneous road trips!',
    ARRAY['https://i.pravatar.cc/300?img=1'],
    ARRAY['Cooking', 'Technology', 'Travel', 'Photography', 'Hiking'],
    NOW() - INTERVAL '30 days',
    NOW() - INTERVAL '5 days'
),
(
    'google_test002',
    'Jordan Rivera',
    25,
    'Yoga instructor and meditation enthusiast. Believer in positive vibes and good coffee. Let''s grab matcha and talk about life!',
    ARRAY['https://i.pravatar.cc/300?img=2'],
    ARRAY['Yoga', 'Fitness', 'Coffee', 'Reading', 'Nature'],
    NOW() - INTERVAL '28 days',
    NOW() - INTERVAL '3 days'
),
(
    'google_test003',
    'Sam Patel',
    31,
    'Marketing strategist with a passion for live music. Concert regular and vinyl collector. Can''t resist a good pun.',
    ARRAY['https://i.pravatar.cc/300?img=3'],
    ARRAY['Music', 'Concerts', 'Marketing', 'Vinyl Records', 'Comedy'],
    NOW() - INTERVAL '25 days',
    NOW() - INTERVAL '7 days'
),
(
    'google_test004',
    'Taylor Kim',
    27,
    'Graphic designer who loves turning coffee into creativity. Weekend warrior at local art galleries. Looking for someone to explore the city with.',
    ARRAY['https://i.pravatar.cc/300?img=4'],
    ARRAY['Art', 'Design', 'Coffee', 'Museums', 'Illustration'],
    NOW() - INTERVAL '22 days',
    NOW() - INTERVAL '2 days'
),
(
    'google_test005',
    'Morgan Santos',
    29,
    'Outdoor enthusiast and rock climbing addict. If I''m not at the gym, I''m probably at the crag. Let''s belay each other through life!',
    ARRAY['https://i.pravatar.cc/300?img=5'],
    ARRAY['Climbing', 'Outdoor Adventures', 'Fitness', 'Photography', 'Travel'],
    NOW() - INTERVAL '20 days',
    NOW() - INTERVAL '1 days'
),
(
    'google_test006',
    'Casey Nguyen',
    26,
    'Elementary school teacher with a love for board games and terrible dad jokes. Looking for a Player 2!',
    ARRAY['https://i.pravatar.cc/300?img=6'],
    ARRAY['Board Games', 'Teaching', 'Reading', 'Comedy', 'Cooking'],
    NOW() - INTERVAL '18 days',
    NOW() - INTERVAL '4 days'
),
(
    'google_test007',
    'Riley Anderson',
    30,
    'Data scientist trying to make sense of the world, one dataset at a time. Love sci-fi, craft beer, and philosophical conversations.',
    ARRAY['https://i.pravatar.cc/300?img=7'],
    ARRAY['Science', 'Beer', 'Books', 'Technology', 'Philosophy'],
    NOW() - INTERVAL '15 days',
    NOW() - INTERVAL '1 days'
),
(
    'google_test008',
    'Avery Williams',
    24,
    'Aspiring photographer capturing the beauty in everyday moments. Dog lover (I have a golden retriever named Sunny). Let''s go on photo walks!',
    ARRAY['https://i.pravatar.cc/300?img=8'],
    ARRAY['Photography', 'Dogs', 'Nature', 'Art', 'Walking'],
    NOW() - INTERVAL '12 days',
    NOW() - INTERVAL '2 days'
),
(
    'google_test009',
    'Drew Martinez',
    32,
    'Entrepreneur building the next big thing. Work hard, play harder. Looking for someone ambitious who can keep up!',
    ARRAY['https://i.pravatar.cc/300?img=9'],
    ARRAY['Entrepreneurship', 'Travel', 'Fitness', 'Technology', 'Wine'],
    NOW() - INTERVAL '10 days',
    NOW() - INTERVAL '1 days'
),
(
    'google_test010',
    'Charlie Lee',
    28,
    'Bookworm and aspiring novelist. If you can recommend a good book, you''ve already won me over. Favorite genre: magical realism.',
    ARRAY['https://i.pravatar.cc/300?img=10'],
    ARRAY['Reading', 'Writing', 'Books', 'Coffee', 'Art'],
    NOW() - INTERVAL '8 days',
    NOW() - INTERVAL '1 days'
),
(
    'google_test011',
    'Jamie Brown',
    26,
    'Personal trainer helping people crush their fitness goals. Meal prep enthusiast and smoothie expert. Let''s get healthy together!',
    ARRAY['https://i.pravatar.cc/300?img=11'],
    ARRAY['Fitness', 'Health', 'Cooking', 'Running', 'Yoga'],
    NOW() - INTERVAL '6 days',
    NOW() - INTERVAL '6 hours'
),
(
    'google_test012',
    'Quinn Davis',
    29,
    'Architect designing spaces where life happens. Lover of modern design and mid-century furniture. Can talk about buildings for hours.',
    ARRAY['https://i.pravatar.cc/300?img=12'],
    ARRAY['Architecture', 'Design', 'Art', 'Travel', 'Photography'],
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '12 hours'
),
(
    'google_test013',
    'Reese Garcia',
    27,
    'Marine biologist passionate about ocean conservation. Scuba certified and always planning the next dive trip. Let''s save the oceans together!',
    ARRAY['https://i.pravatar.cc/300?img=13'],
    ARRAY['Scuba Diving', 'Ocean', 'Travel', 'Science', 'Photography'],
    NOW() - INTERVAL '4 days',
    NOW() - INTERVAL '4 hours'
),
(
    'google_test014',
    'Skylar Wilson',
    25,
    'Pastry chef who believes life is too short for bad desserts. Weekend brunch enthusiast. I''ll bake you cookies on the first date!',
    ARRAY['https://i.pravatar.cc/300?img=14'],
    ARRAY['Baking', 'Cooking', 'Food', 'Coffee', 'Travel'],
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '3 hours'
),
(
    'google_test015',
    'Blake Moore',
    30,
    'Lawyer by profession, comedian by heart. Improv classes keep me sane. Looking for someone who appreciates good humor and better debates.',
    ARRAY['https://i.pravatar.cc/300?img=15'],
    ARRAY['Comedy', 'Improv', 'Debate', 'Theater', 'Reading'],
    NOW() - INTERVAL '2 days',
    NOW() - INTERVAL '2 hours'
),
(
    'google_test016',
    'Phoenix Taylor',
    28,
    'DJ spinning records and good vibes. Music festival regular. Life''s a party, and I''m always looking for the next adventure.',
    ARRAY['https://i.pravatar.cc/300?img=16'],
    ARRAY['Music', 'DJing', 'Festivals', 'Dancing', 'Travel'],
    NOW() - INTERVAL '1 days',
    NOW() - INTERVAL '1 hour'
),
(
    'google_test017',
    'Sage Jackson',
    26,
    'Veterinarian who thinks all animals are perfect. Proud plant parent with 30+ houseplants. Let''s talk about your pets for hours!',
    ARRAY['https://i.pravatar.cc/300?img=17'],
    ARRAY['Animals', 'Veterinary', 'Plants', 'Nature', 'Hiking'],
    NOW() - INTERVAL '12 hours',
    NOW() - INTERVAL '30 minutes'
),
(
    'google_test018',
    'Dakota White',
    31,
    'Financial advisor who actually makes money interesting. Love traveling on points and finding the best deals. Let me plan our vacation!',
    ARRAY['https://i.pravatar.cc/300?img=18'],
    ARRAY['Travel', 'Finance', 'Hiking', 'Wine', 'Photography'],
    NOW() - INTERVAL '6 hours',
    NOW() - INTERVAL '15 minutes'
),
(
    'google_test019',
    'River Harris',
    24,
    'Video game developer living the dream. Gamer, anime fan, and bubble tea addict. Looking for a co-op partner in life!',
    ARRAY['https://i.pravatar.cc/300?img=19'],
    ARRAY['Gaming', 'Anime', 'Technology', 'Coding', 'Esports'],
    NOW() - INTERVAL '3 hours',
    NOW() - INTERVAL '10 minutes'
),
(
    'google_test020',
    'Ocean Clark',
    27,
    'Environmental scientist fighting climate change. Vegan foodie and zero-waste advocate. Let''s make the world a better place, one date at a time.',
    ARRAY['https://i.pravatar.cc/300?img=20'],
    ARRAY['Environment', 'Sustainability', 'Vegan', 'Science', 'Activism'],
    NOW() - INTERVAL '1 hour',
    NOW() - INTERVAL '5 minutes'
)
ON CONFLICT (user_id) DO NOTHING;

-- ============================================================================
-- TEST MATCHES
-- ============================================================================
-- Create realistic match patterns

INSERT INTO matches (id, user_id_1, user_id_2, created_at) VALUES
-- Recent matches (active conversations)
('test_match_001', 'google_test001', 'google_test002', NOW() - INTERVAL '5 days'),
('test_match_002', 'google_test001', 'google_test005', NOW() - INTERVAL '4 days'),
('test_match_003', 'google_test001', 'google_test010', NOW() - INTERVAL '3 days'),
('test_match_004', 'google_test002', 'google_test006', NOW() - INTERVAL '6 days'),
('test_match_005', 'google_test002', 'google_test011', NOW() - INTERVAL '2 days'),
('test_match_006', 'google_test003', 'google_test004', NOW() - INTERVAL '7 days'),
('test_match_007', 'google_test003', 'google_test016', NOW() - INTERVAL '1 day'),
('test_match_008', 'google_test004', 'google_test012', NOW() - INTERVAL '5 days'),
('test_match_009', 'google_test005', 'google_test013', NOW() - INTERVAL '3 days'),
('test_match_010', 'google_test006', 'google_test008', NOW() - INTERVAL '4 days'),
-- Older matches (less active)
('test_match_011', 'google_test007', 'google_test019', NOW() - INTERVAL '10 days'),
('test_match_012', 'google_test008', 'google_test017', NOW() - INTERVAL '8 days'),
('test_match_013', 'google_test009', 'google_test018', NOW() - INTERVAL '9 days'),
('test_match_014', 'google_test010', 'google_test014', NOW() - INTERVAL '7 days'),
('test_match_015', 'google_test011', 'google_test012', NOW() - INTERVAL '6 days'),
-- Very recent matches (just matched)
('test_match_016', 'google_test015', 'google_test020', NOW() - INTERVAL '2 hours'),
('test_match_017', 'google_test016', 'google_test019', NOW() - INTERVAL '4 hours'),
('test_match_018', 'google_test017', 'google_test020', NOW() - INTERVAL '6 hours'),
('test_match_019', 'google_test001', 'google_test015', NOW() - INTERVAL '1 hour'),
('test_match_020', 'google_test003', 'google_test007', NOW() - INTERVAL '30 minutes')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- TEST MESSAGES
-- ============================================================================
-- Create realistic conversation threads

-- Conversation 1: Alex & Jordan (active, flirty)
INSERT INTO messages (id, match_id, sender_id, text, created_at) VALUES
('test_msg_001', 'test_match_001', 'google_test001', 'Hey! I saw you''re into yoga. I''ve been meaning to start - any tips for a total beginner? 😅', NOW() - INTERVAL '5 days'),
('test_msg_002', 'test_match_001', 'google_test002', 'Hi Alex! That''s awesome! Start with beginner classes and don''t push yourself too hard. It''s about the journey, not perfection!', NOW() - INTERVAL '5 days' + INTERVAL '30 minutes'),
('test_msg_003', 'test_match_001', 'google_test001', 'Love that mindset! Do you have a favorite studio you''d recommend?', NOW() - INTERVAL '5 days' + INTERVAL '1 hour'),
('test_msg_004', 'test_match_001', 'google_test002', 'I teach at Zen Flow on Saturdays! You should come by sometime 😊', NOW() - INTERVAL '5 days' + INTERVAL '2 hours'),
('test_msg_005', 'test_match_001', 'google_test001', 'That sounds perfect! I''ll check it out this weekend. Maybe grab coffee after?', NOW() - INTERVAL '4 days'),
('test_msg_006', 'test_match_001', 'google_test002', 'I''d love that! Fair warning though, I''ll be all sweaty from class 😂', NOW() - INTERVAL '4 days' + INTERVAL '15 minutes'),
('test_msg_007', 'test_match_001', 'google_test001', 'Haha, that''s totally fine! Looking forward to it!', NOW() - INTERVAL '4 days' + INTERVAL '30 minutes'),
('test_msg_008', 'test_match_001', 'google_test002', 'Hey! Did you make it to class? I didn''t see you there', NOW() - INTERVAL '3 days'),
('test_msg_009', 'test_match_001', 'google_test001', 'Oh no! I got called into work at the last minute 😭 Can we reschedule?', NOW() - INTERVAL '3 days' + INTERVAL '1 hour'),
('test_msg_010', 'test_match_001', 'google_test002', 'Of course! How about next Saturday?', NOW() - INTERVAL '2 days'),

-- Conversation 2: Alex & Morgan (outdoor adventure vibes)
('test_msg_011', 'test_match_002', 'google_test005', 'Rock climbing AND cooking? That''s my kind of person! 🧗‍♀️', NOW() - INTERVAL '4 days'),
('test_msg_012', 'test_match_002', 'google_test001', 'Haha thanks! Gotta fuel those climbs somehow. Do you have a favorite spot?', NOW() - INTERVAL '4 days' + INTERVAL '20 minutes'),
('test_msg_013', 'test_match_002', 'google_test005', 'I''m obsessed with Red Rock right now. The routes there are incredible!', NOW() - INTERVAL '4 days' + INTERVAL '1 hour'),
('test_msg_014', 'test_match_002', 'google_test001', 'I''ve been dying to go there! Have any route recommendations?', NOW() - INTERVAL '3 days'),
('test_msg_015', 'test_match_002', 'google_test005', 'So many! We should go together sometime. I can show you the ropes (literally 😂)', NOW() - INTERVAL '3 days' + INTERVAL '30 minutes'),

-- Conversation 3: Alex & Charlie (book lovers)
('test_msg_016', 'test_match_003', 'google_test010', 'A fellow foodie who loves road trips? Tell me your best road trip food story!', NOW() - INTERVAL '3 days'),
('test_msg_017', 'test_match_003', 'google_test001', 'Oh man, I once drove 3 hours for this legendary taco truck I read about. Totally worth it!', NOW() - INTERVAL '3 days' + INTERVAL '15 minutes'),
('test_msg_018', 'test_match_003', 'google_test010', 'That''s dedication! I respect that. What''s your favorite cuisine to cook?', NOW() - INTERVAL '2 days'),
('test_msg_019', 'test_match_003', 'google_test001', 'Italian pasta dishes. There''s something therapeutic about making fresh pasta from scratch', NOW() - INTERVAL '2 days' + INTERVAL '45 minutes'),
('test_msg_020', 'test_match_003', 'google_test010', 'Okay now I''m hungry 😂 You''ll have to cook for me sometime!', NOW() - INTERVAL '1 day'),

-- Conversation 4: Jordan & Casey (fun and lighthearted)
('test_msg_021', 'test_match_004', 'google_test006', 'A yoga instructor who loves good coffee? I think we''re cosmically aligned ☕🧘', NOW() - INTERVAL '6 days'),
('test_msg_022', 'test_match_004', 'google_test002', 'Haha I love that! What''s your go-to coffee order?', NOW() - INTERVAL '6 days' + INTERVAL '10 minutes'),
('test_msg_023', 'test_match_004', 'google_test006', 'Oat milk latte with an extra shot. I teach elementary school - I need all the caffeine I can get 😅', NOW() - INTERVAL '5 days'),
('test_msg_024', 'test_match_004', 'google_test002', 'Oh wow, teaching takes so much energy! Mad respect. What grade?', NOW() - INTERVAL '5 days' + INTERVAL '2 hours'),
('test_msg_025', 'test_match_004', 'google_test006', '3rd grade! They''re at that perfect age where they''re curious about everything', NOW() - INTERVAL '4 days'),

-- Conversation 5: Sam & Taylor (creative minds)
('test_msg_026', 'test_match_006', 'google_test004', 'Marketing + music = the perfect combo! What''s the last concert you went to?', NOW() - INTERVAL '7 days'),
('test_msg_027', 'test_match_006', 'google_test003', 'Saw Japanese Breakfast last month. Absolutely phenomenal! How about you?', NOW() - INTERVAL '7 days' + INTERVAL '1 hour'),
('test_msg_028', 'test_match_006', 'google_test004', 'Jealous! I caught Tame Impala a few weeks ago. The visuals were mind-blowing', NOW() - INTERVAL '6 days'),
('test_msg_029', 'test_match_006', 'google_test003', 'Their shows are legendary! We should go to a concert together', NOW() - INTERVAL '6 days' + INTERVAL '3 hours'),

-- Conversation 6: Sam & Phoenix (music lovers unite)
('test_msg_030', 'test_match_007', 'google_test016', 'A fellow music lover! What''s spinning on your turntable right now? 🎶', NOW() - INTERVAL '1 day'),
('test_msg_031', 'test_match_007', 'google_test003', 'Currently obsessed with this vintage Fleetwood Mac pressing. The warmth is *chef''s kiss*', NOW() - INTERVAL '1 day' + INTERVAL '20 minutes'),
('test_msg_032', 'test_match_007', 'google_test016', 'Classic choice! Ever been to a vinyl swap meet? There''s one this weekend', NOW() - INTERVAL '12 hours'),

-- Conversation 7: Just matched, no messages yet
-- (test_match_016, test_match_017, test_match_018 have no messages)

-- Conversation 8: Recent match with first message
('test_msg_033', 'test_match_019', 'google_test015', 'Hey Alex! Your profile made me smile. Software engineer AND amateur chef? I might need cooking lessons! 👨‍🍳', NOW() - INTERVAL '1 hour'),

('test_msg_034', 'test_match_020', 'google_test007', 'Live music and good puns? You had me at "Can''t resist a good pun" 😄', NOW() - INTERVAL '30 minutes'),
('test_msg_035', 'test_match_020', 'google_test003', 'Haha well I hope you''re ready because I''ve got a million of them!', NOW() - INTERVAL '15 minutes')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- This script creates:
-- - 20 test users (google_test001 through google_test020)
-- - 20 diverse profiles with realistic bios and interests
-- - 20 matches showing various relationship stages
-- - 35+ messages across multiple conversations
--
-- To use these test accounts, you'll need to:
-- 1. Generate JWT tokens for these user IDs using your auth service
-- 2. Or create a test login endpoint that accepts test user IDs
--
-- Clean up test data:
-- DELETE FROM messages WHERE match_id LIKE 'test_%';
-- DELETE FROM matches WHERE id LIKE 'test_%';
-- DELETE FROM profiles WHERE user_id LIKE 'google_test%';
-- DELETE FROM users WHERE id LIKE 'google_test%';
