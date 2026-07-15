CREATE TABLE users_min (id serial primary key, display_name text not null);
CREATE TABLE posts_min (id serial primary key, author_id integer references users_min(id));

INSERT INTO users_min (display_name) SELECT 'user ' || g FROM generate_series(1, 1000) g;
INSERT INTO posts_min (author_id) VALUES (1), (2), (NULL);
ANALYZE users_min;
ANALYZE posts_min;
