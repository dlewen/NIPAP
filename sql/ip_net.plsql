--------------------------------------------
--
-- The basic table structure and similar
--
--------------------------------------------

CREATE TYPE ip_net_plan_type AS ENUM ('reservation', 'assignment', 'host');

CREATE TYPE priority_3step AS ENUM ('low', 'medium', 'high');


--
-- This is where we store "schemas"
-- think of them as something like namespaces for our address plans
-- one would typically be the global one where all public addresses go
-- then we could have several for RFC1918 space to avoid collisions
--
CREATE TABLE ip_net_schema (
	id serial PRIMARY KEY,
	name text UNIQUE,
	description text
);

COMMENT ON TABLE ip_net_schema IS 'IP Address schemas, something like namespaces for our address plan';


--
-- This table is used to store our pools. pools are for a specific
-- purpose and when you need a specific type of address, ie a core
-- loopback or similar, you'll just pick the right pool and get an
-- address assigned automatically.
--
CREATE TABLE ip_net_pool (
	id serial PRIMARY KEY,
	name text UNIQUE,
	schema integer REFERENCES ip_net_schema (id) ON UPDATE CASCADE ON DELETE CASCADE DEFAULT 1,
	description text,
	default_type ip_net_plan_type NOT NULL DEFAULT 'reservation',
	ipv4_default_prefix_length integer,
	ipv6_default_prefix_length integer
);

COMMENT ON TABLE ip_net_pool IS 'IP Pools for assigning prefixes from';


--
-- this table stores the actual prefixes in the address plan, or net 
-- plan as I prefer to call it
--
-- pool is the pool for which this prefix is part of and from which 
-- assignments can be made
--
CREATE TABLE ip_net_plan (
	id serial PRIMARY KEY,
	family integer CHECK(family = 4 OR family = 6),
	schema integer NOT NULL REFERENCES ip_net_schema (id) ON UPDATE CASCADE ON DELETE CASCADE DEFAULT 1,
	prefix cidr NOT NULL,
	display_prefix inet,
	description text,
	comment text,
	node text,
	pool integer REFERENCES ip_net_pool (id) ON UPDATE CASCADE ON DELETE SET NULL,
	type ip_net_plan_type NOT NULL DEFAULT 'reservation',
	indent integer,
	country text,
	span_order integer,
	authoritative_source text NOT NULL,
	alarm_priority priority_3step NOT NULL DEFAULT 'high'
);

COMMENT ON TABLE ip_net_plan IS 'Actual address / prefix plan';

COMMENT ON COLUMN ip_net_plan.family IS 'Address family, either ''4'' for IPv4 or ''6'' for IPv6';
COMMENT ON COLUMN ip_net_plan.schema IS 'Address-schema';
COMMENT ON COLUMN ip_net_plan.prefix IS '"true" IP prefix, with hosts registered as /32';
COMMENT ON COLUMN ip_net_plan.display_prefix IS 'IP prefix with hosts having their covering assignments prefix-length';
COMMENT ON COLUMN ip_net_plan.description IS 'Prefix description';
COMMENT ON COLUMN ip_net_plan.comment IS 'Comment!';
COMMENT ON COLUMN ip_net_plan.node IS 'FQDN of the IP node where the prefix is/should be configured on';
COMMENT ON COLUMN ip_net_plan.pool IS 'Pool that this prefix is part of';
COMMENT ON COLUMN ip_net_plan.type IS 'Type is one of "reservation", "assignment" or "host"';
COMMENT ON COLUMN ip_net_plan.indent IS 'Number of indents to properly render this prefix';
COMMENT ON COLUMN ip_net_plan.country IS 'ISO3166-1 two letter country code';
COMMENT ON COLUMN ip_net_plan.span_order IS 'SPAN order';
COMMENT ON COLUMN ip_net_plan.authoritative_source IS 'The authoritative source for information regarding this prefix';
COMMENT ON COLUMN ip_net_plan.alarm_priority IS 'Priority of alarms sent for this prefix to NetWatch.';

CREATE UNIQUE INDEX ip_net_plan__schema_prefix__index ON ip_net_plan (schema, prefix);
CREATE INDEX ip_net_plan__node__index ON ip_net_plan (node);


CREATE OR REPLACE FUNCTION tf_ip_net_prefix_family_before() RETURNS trigger AS $$
DECLARE
	r RECORD;
BEGIN
	NEW.family = family(NEW.prefix);
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ip_net_pool_prefix__iu_before
	BEFORE UPDATE OR INSERT
	ON ip_net_plan
	FOR EACH ROW
	EXECUTE PROCEDURE tf_ip_net_prefix_family_before();


CREATE OR REPLACE FUNCTION tf_ip_net_prefix_family_after() RETURNS trigger AS $$
DECLARE
	r RECORD;
BEGIN
	IF TG_OP = 'DELETE' THEN
		PERFORM calc_indent(OLD.prefix);
	ELSE
		PERFORM calc_indent(NEW.prefix);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ip_net_pool_prefix__iu_after
	AFTER DELETE OR INSERT OR UPDATE
	ON ip_net_plan
	FOR EACH ROW
	EXECUTE PROCEDURE tf_ip_net_prefix_family_after();


GRANT ALL ON ip_net_plan TO napd;
GRANT USAGE ON ip_net_plan_id_seq TO napd;
GRANT ALL ON ip_net_pool TO napd;
GRANT USAGE ON ip_net_pool_id_seq TO napd;
GRANT ALL ON ip_net_schema TO napd;
GRANT USAGE ON ip_net_schema_id_seq TO napd;

--
-- example data
--

-- though you probably always want this
INSERT INTO ip_net_schema (name, description) VALUES ('global', 'Global address plan, ie the Internet');

INSERT INTO ip_net_pool (name, description, ipv4_default_prefix_length, ipv6_default_prefix_lenth) VALUES ('tele2-infrastructure', 'Tele2 Infrastructure allocation', 0, 0);

INSERT INTO ip_net_pool (name, description, ipv4_default_prefix_length, ipv6_default_prefix_lenth) VALUES ('loopback', 'loopback addresses for routers', 32, 128);

INSERT INTO ip_net_plan(prefix, description, pool, authoritative_source) VALUES ('130.244.0.0/16', 'Tele2s good ol'' /16', (SELECT id FROM ip_net_pool WHERE name='tele2-infrastructure'), 'nap');
INSERT INTO ip_net_plan(prefix, description, pool, authoritative_source) VALUES ('212.151.0.0/16', 'Tele2s middle age /16', (SELECT id FROM ip_net_pool WHERE name='tele2-infrastructure'), 'nap');

INSERT INTO ip_net_plan(prefix, description, pool, authoritative_source) VALUES ('2a00:800::/25', 'Tele2s funky new /25', (SELECT id FROM ip_net_pool WHERE name='tele2-block'), 'nap');



