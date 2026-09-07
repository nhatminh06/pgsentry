-- comments and semicolons inside strings must not split statements
SET lock_timeout = '1500ms';
CREATE INDEX CONCURRENTLY "idx;odd" ON "sales"."Order Items" ("order;id");
INSERT INTO public.audit_messages(message) VALUES ('not SQL; DROP TABLE users;');
