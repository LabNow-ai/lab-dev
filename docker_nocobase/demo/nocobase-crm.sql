/*
  NocoBase fresh-database bootstrap (PostgreSQL) - "public" schema
  - Standalone initial DDL for CRM/meta tables (prefixed with "t_crm_" or "t_meta_")
  - Sequence + DEFAULT nextval(...)
  - Physical foreign key constraints, M2M junction tables (t_crm_customerTags, t_crm_teamMembers) & O2M tables (t_crm_customerRecords, t_crm_contactMethods)
  - Built-in NocoBase metadata registration (categories, collections & fields)
  - Association metadata (m2o, m2m, o2m / belongsTo, belongsToMany, hasMany)
  - Collection sort numbers starting from 101
  - Snowflake ID style primary keys with id column
*/

-- =========================================================
-- 0. Utility function for business code generation
-- =========================================================
CREATE OR REPLACE FUNCTION generate_biz_code(
    p_prefix text,
    p_with_date boolean DEFAULT false,
    p_length int DEFAULT 6,
    p_charset text DEFAULT 'base32'
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_charset text;
    v_result text := '';
    v_date text;
    i int;
    v_index int;
BEGIN
    IF p_length < 1 OR p_length > 32 THEN
        RAISE EXCEPTION 'length must be between 1 and 32';
    END IF;

    CASE lower(p_charset)
        WHEN 'numeric' THEN v_charset := '0123456789';
        WHEN 'alphanumeric' THEN v_charset := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        WHEN 'base32' THEN v_charset := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
        ELSE
            RAISE EXCEPTION 'unsupported charset: %, allowed: numeric, alphanumeric, base32', p_charset;
    END CASE;

    FOR i IN 1..p_length LOOP
        v_index :=
            floor(
                random() * length(v_charset)
            )::int + 1;
        v_result := v_result || substr(v_charset, v_index, 1);
    END LOOP;

    IF p_with_date THEN
        v_date := to_char(current_date, 'YYYYMMDD');
        RETURN format('%s-%s-%s', upper(p_prefix), v_date, v_result);
    ELSE
        RETURN format('%s-%s', upper(p_prefix), v_result);
    END IF;
END;
$$;

-- =========================================================
-- 1. Reset existing objects for a fresh bootstrap
-- =========================================================
DROP TABLE IF EXISTS "t_crm_orderItems" CASCADE;
DROP TABLE IF EXISTS "t_crm_orders" CASCADE;
DROP TABLE IF EXISTS "t_meta_skus" CASCADE;
DROP TABLE IF EXISTS "t_meta_spus" CASCADE;
DROP TABLE IF EXISTS "t_crm_customerTags" CASCADE;
DROP TABLE IF EXISTS "t_crm_customerRecords" CASCADE;
DROP TABLE IF EXISTS "t_crm_contactMethods" CASCADE;
DROP TABLE IF EXISTS "t_crm_teamMembers" CASCADE;
DROP TABLE IF EXISTS "t_crm_teams" CASCADE;
DROP TABLE IF EXISTS "t_crm_tags" CASCADE;
DROP TABLE IF EXISTS "t_crm_customer" CASCADE;

DROP SEQUENCE IF EXISTS "t_crm_customer_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_tags_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_customerTags_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_customerRecords_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_contactMethods_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_teams_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_teamMembers_id_seq";
DROP SEQUENCE IF EXISTS "t_meta_spus_id_seq";
DROP SEQUENCE IF EXISTS "t_meta_skus_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_orders_id_seq";
DROP SEQUENCE IF EXISTS "t_crm_orderItems_id_seq";

CREATE SEQUENCE IF NOT EXISTS "t_crm_customer_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_tags_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_customerTags_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_customerRecords_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_contactMethods_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_teams_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_teamMembers_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_meta_spus_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_meta_skus_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_orders_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_orderItems_id_seq";

-- =========================================================
-- 2. Main tables (Audit columns placed immediately after id)
-- =========================================================

CREATE TABLE IF NOT EXISTS "t_crm_teams" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_teams_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('TEAM', false, 5, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "name" character varying(255) NOT NULL,
  "description" text,
  "state" character varying(255) DEFAULT 'active',
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_teams_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_teamMembers" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_teamMembers_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('TMBR', false, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "teamId" bigint NOT NULL,
  "userId" bigint NOT NULL,
  "role" character varying(255) DEFAULT 'member',
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_teamMembers_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_teamMembers_teamId_userId_uk" UNIQUE ("teamId", "userId"),
  CONSTRAINT "t_crm_teamMembers_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "t_crm_teams"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "t_crm_customer" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_customer_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('CUST', false, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "assigneeId" bigint,
  "teamId" bigint,
  "name" character varying(255),
  "phone" character varying(255),
  "addr" text,
  "age" bigint,
  "gender" character varying(255),
  "state" character varying(255) DEFAULT 'sea',
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_customer_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_customer_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "t_crm_teams"("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "t_crm_tags" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_tags_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('TAG', false, 5, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "dimension" character varying(255),
  "tag" character varying(255),
  "state" character varying(255) DEFAULT '0',
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_tags_pkey" PRIMARY KEY ("id")
);

-- Many-to-Many Junction Table between t_crm_customer and t_crm_tags
CREATE TABLE IF NOT EXISTS "t_crm_customerTags" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_customerTags_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('CTAG', false, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "customer" bigint NOT NULL,
  "tag" bigint NOT NULL,
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_customerTags_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_customerTags_customer_tag_uk" UNIQUE ("customer", "tag"),
  CONSTRAINT "t_crm_customerTags_customer_fkey" FOREIGN KEY ("customer") REFERENCES "t_crm_customer"("id") ON DELETE CASCADE,
  CONSTRAINT "t_crm_customerTags_tag_fkey" FOREIGN KEY ("tag") REFERENCES "t_crm_tags"("id") ON DELETE CASCADE
);

-- One-to-Many Table for Customer Multi-Channel Contact Methods
CREATE TABLE IF NOT EXISTS "t_crm_contactMethods" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_contactMethods_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('CMTD', false, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "customerId" bigint NOT NULL,
  "channel" character varying(255) NOT NULL,
  "account" character varying(255) NOT NULL,
  "isPrimary" boolean DEFAULT false,
  "verified" boolean DEFAULT false,
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_contactMethods_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_contactMethods_customerId_channel_account_uk" UNIQUE ("customerId", "channel", "account"),
  CONSTRAINT "t_crm_contactMethods_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "t_crm_customer"("id") ON DELETE CASCADE
);

-- One-to-Many Table for Customer Communication Records
CREATE TABLE IF NOT EXISTS "t_crm_customerRecords" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_customerRecords_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('CREC', true, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "customerId" bigint NOT NULL,
  "contactMethodId" bigint,
  "title" character varying(255),
  "type" character varying(255) DEFAULT 'call',
  "content" text,
  "recordTime" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_customerRecords_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_customerRecords_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "t_crm_customer"("id") ON DELETE CASCADE,
  CONSTRAINT "t_crm_customerRecords_contactMethodId_fkey" FOREIGN KEY ("contactMethodId") REFERENCES "t_crm_contactMethods"("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "t_meta_spus" (
  "id" bigint NOT NULL DEFAULT nextval('"t_meta_spus_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('SPU', false, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "productName" character varying(255) NOT NULL,
  "spec" character varying(255),
  "baseUnit" character varying(255),
  "unitMeasureValue" double precision NOT NULL,
  "unitMeasureUnit" character varying(255),
  "spuDisplayName" character varying(255),
  "data1" text,
  "data2" text,
  CONSTRAINT "t_meta_spus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_meta_skus" (
  "id" bigint NOT NULL DEFAULT nextval('"t_meta_skus_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('SKU', false, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "spuId" bigint,
  "packageQty" double precision NOT NULL,
  "saleUnit" character varying(255),
  "skuDisplayName" text NOT NULL,
  "salePrice" double precision NOT NULL,
  "data1" text,
  "data2" text,
  CONSTRAINT "t_meta_skus_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_meta_skus_spuId_fkey" FOREIGN KEY ("spuId") REFERENCES "t_meta_spus"("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "t_crm_orders" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_orders_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('ORD', true, 6, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "customerId" bigint,
  "status" character varying(255) DEFAULT 'pending',
  "total" double precision,
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_orders_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_orders_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "t_crm_customer"("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "t_crm_orderItems" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_orderItems_id_seq"'::regclass),
  "code" character varying(64) NOT NULL DEFAULT generate_biz_code('ITEM', true, 7, 'base32'),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "skuId" bigint,
  "orderId" bigint,
  "quantity" double precision NOT NULL,
  "unitPrice" double precision NOT NULL,
  "data1" text,
  "data2" text,
  CONSTRAINT "t_crm_orderItems_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_orderItems_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "t_meta_skus"("id") ON DELETE SET NULL,
  CONSTRAINT "t_crm_orderItems_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "t_crm_orders"("id") ON DELETE CASCADE
);

-- =========================================================
-- 3. Bind sequence ownership & indexes
-- =========================================================
ALTER SEQUENCE "t_crm_teams_id_seq" OWNED BY "t_crm_teams"."id";
ALTER SEQUENCE "t_crm_teamMembers_id_seq" OWNED BY "t_crm_teamMembers"."id";
ALTER SEQUENCE "t_crm_customer_id_seq" OWNED BY "t_crm_customer"."id";
ALTER SEQUENCE "t_crm_contactMethods_id_seq" OWNED BY "t_crm_contactMethods"."id";
ALTER SEQUENCE "t_crm_tags_id_seq" OWNED BY "t_crm_tags"."id";
ALTER SEQUENCE "t_crm_customerTags_id_seq" OWNED BY "t_crm_customerTags"."id";
ALTER SEQUENCE "t_crm_customerRecords_id_seq" OWNED BY "t_crm_customerRecords"."id";
ALTER SEQUENCE "t_meta_spus_id_seq" OWNED BY "t_meta_spus"."id";
ALTER SEQUENCE "t_meta_skus_id_seq" OWNED BY "t_meta_skus"."id";
ALTER SEQUENCE "t_crm_orders_id_seq" OWNED BY "t_crm_orders"."id";
ALTER SEQUENCE "t_crm_orderItems_id_seq" OWNED BY "t_crm_orderItems"."id";

CREATE INDEX IF NOT EXISTS "t_crm_customer_assignee_id_idx" ON "t_crm_customer" ("assigneeId");
CREATE INDEX IF NOT EXISTS "t_crm_customer_teamId_idx" ON "t_crm_customer" ("teamId");
CREATE INDEX IF NOT EXISTS "t_crm_contactMethods_customerId_idx" ON "t_crm_contactMethods" ("customerId");
CREATE INDEX IF NOT EXISTS "t_crm_customerRecords_customerId_idx" ON "t_crm_customerRecords" ("customerId");
CREATE INDEX IF NOT EXISTS "t_crm_customerRecords_contactMethodId_idx" ON "t_crm_customerRecords" ("contactMethodId");
CREATE INDEX IF NOT EXISTS "t_crm_teamMembers_teamId_idx" ON "t_crm_teamMembers" ("teamId");
CREATE INDEX IF NOT EXISTS "t_crm_teamMembers_userId_idx" ON "t_crm_teamMembers" ("userId");
CREATE INDEX IF NOT EXISTS "t_crm_orders_customerId_idx" ON "t_crm_orders" ("customerId");
CREATE INDEX IF NOT EXISTS "t_crm_orderItems_skuId_idx" ON "t_crm_orderItems" ("skuId");
CREATE INDEX IF NOT EXISTS "t_crm_orderItems_orderId_idx" ON "t_crm_orderItems" ("orderId");
CREATE INDEX IF NOT EXISTS "t_crm_tags_dimension_idx" ON "t_crm_tags" ("dimension");

-- =========================================================
-- 4. NocoBase System Metadata Registration (Batch Operations)
-- =========================================================

-- 4.1 Collection Category Registration ('CRM' and 'meta')
INSERT INTO "collectionCategories" ("id", "name", "color", "sort", "createdAt", "updatedAt")
SELECT (EXTRACT(EPOCH FROM NOW())::bigint * 1000), 'CRM', 'magenta', 1, NOW(), NOW()
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategories')
  AND NOT EXISTS (SELECT 1 FROM "collectionCategories" WHERE "name" = 'CRM');

INSERT INTO "collectionCategories" ("id", "name", "color", "sort", "createdAt", "updatedAt")
SELECT (EXTRACT(EPOCH FROM NOW())::bigint * 1000 + 1), 'meta', 'cyan', 2, NOW(), NOW()
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategories')
  AND NOT EXISTS (SELECT 1 FROM "collectionCategories" WHERE "name" = 'meta');

INSERT INTO "collectionCategory" ("categoryId", "collectionName", "createdAt", "updatedAt")
SELECT c.id, col.name, NOW(), NOW()
FROM "collectionCategories" c
CROSS JOIN (VALUES ('t_crm_customer'), ('t_crm_contactMethods'), ('t_crm_tags'), ('t_crm_customerTags'), ('t_crm_customerRecords'), ('t_crm_teams'), ('t_crm_teamMembers'), ('t_meta_spus'), ('t_meta_skus'), ('t_crm_orders'), ('t_crm_orderItems')) AS col(name)
WHERE c.name = 'CRM'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategory')
  AND NOT EXISTS (
    SELECT 1 FROM "collectionCategory" cc WHERE cc."categoryId" = c.id AND cc."collectionName" = col.name
  );

INSERT INTO "collectionCategory" ("categoryId", "collectionName", "createdAt", "updatedAt")
SELECT c.id, col.name, NOW(), NOW()
FROM "collectionCategories" c
CROSS JOIN (VALUES ('t_meta_spus'), ('t_meta_skus')) AS col(name)
WHERE c.name = 'meta'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategory')
  AND NOT EXISTS (
    SELECT 1 FROM "collectionCategory" cc WHERE cc."categoryId" = c.id AND cc."collectionName" = col.name
  );

-- 4.2 Collections Registration & Target Key Configuration (sort starting from 101)
INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options", "sort")
SELECT
  v.name,
  v.name,
  v.title,
  false,
  v.hidden_val,
  v.opts::json,
  v.sort_val
FROM (VALUES
  ('t_crm_teams', '跟进团队', false, 101, '{"template": "general", "tableName": "t_crm_teams", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "name", "unavailableActions": []}'),
  ('t_crm_teamMembers', '团队成员', false, 102, '{"template": "general", "tableName": "t_crm_teamMembers", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "code", "unavailableActions": []}'),
  ('t_crm_tags', '标签', false, 100, '{"template": "general", "tableName": "t_crm_tags", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "tag", "unavailableActions": []}'),
  ('t_crm_customer', '顾客', false, 110, '{"template": "general", "tableName": "t_crm_customer", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "name", "unavailableActions": []}'),
  ('t_crm_contactMethods', '顾客联系方式', false, 111, '{"template": "general", "tableName": "t_crm_contactMethods", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "account", "unavailableActions": []}'),
  ('t_crm_customerTags', '顾客标签', true, 112, '{"template": "general", "timestamps": true, "autoGenId": true, "autoCreate": true, "isThrough": true, "sortable": false}'),
  ('t_crm_customerRecords', '顾客沟通记录', false, 113, '{"template": "general", "tableName": "t_crm_customerRecords", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "title", "unavailableActions": []}'),
  ('t_meta_spus', '产品(SPU)', false, 121, '{"template": "general", "tableName": "t_meta_spus", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "productName", "unavailableActions": []}'),
  ('t_meta_skus', '商品规格(SKU)', false, 122, '{"template": "general", "tableName": "t_meta_skus", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "skuDisplayName", "unavailableActions": []}'),
  ('t_crm_orders', '订单', false, 131, '{"template": "general", "tableName": "t_crm_orders", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "code", "unavailableActions": []}'),
  ('t_crm_orderItems', '订单明细', false, 132, '{"template": "general", "tableName": "t_crm_orderItems", "timestamps": false, "autoGenId": true, "from": "dbsync", "underscored": false, "titleField": "code", "unavailableActions": []}')
) AS v(name, title, hidden_val, sort_val, opts)
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
ON CONFLICT ("name") DO UPDATE SET
  "title" = EXCLUDED."title",
  "hidden" = EXCLUDED."hidden",
  "sort" = EXCLUDED."sort",
  "options" = EXCLUDED."options";

-- 4.3 Fields Registration & Display Titles (Including Foreign Key, M2M & O2M Association Fields)
DELETE FROM "fields"
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fields')
  AND "collectionName" IN ('t_crm_customer', 't_crm_contactMethods', 't_crm_customerRecords', 't_crm_tags', 't_crm_customerTags', 't_crm_teams', 't_crm_teamMembers', 't_meta_spus', 't_meta_skus', 't_crm_orders', 't_crm_orderItems');

INSERT INTO "fields" ("key", "name", "type", "interface", "options", "collectionName", "sort")
SELECT
  'f_' || v.col_name || '_' || v.f_name,
  v.f_name,
  v.f_type,
  v.f_iface,
  v.opts::json,
  v.col_name,
  v.sort_val
FROM (VALUES
  -- t_crm_teams
  ('t_crm_teams', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_teams', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_teams', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_teams', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_teams', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_teams', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_teams', 'name', 'string', 'input', '{"allowNull": false, "field": "name", "uiSchema": {"type": "string", "title": "团队名称", "x-component": "Input"}}', 7),
  ('t_crm_teams', 'description', 'text', 'textarea', '{"allowNull": true, "field": "description", "uiSchema": {"type": "string", "title": "团队描述", "x-component": "Input.TextArea"}}', 8),
  ('t_crm_teams', 'state', 'string', 'select', '{"allowNull": true, "field": "state", "defaultValue": "active", "uiSchema": {"type": "string", "title": "团队状态", "x-component": "Select", "enum": [{"value": "active", "label": "活跃", "color": "green"}, {"value": "archived", "label": "已归档", "color": "default"}]}}', 9),
  ('t_crm_teams', 'members', 'hasMany', 'o2m', '{"target": "t_crm_teamMembers", "foreignKey": "teamId", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "团队成员", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 10),
  ('t_crm_teams', 'customers', 'hasMany', 'o2m', '{"target": "t_crm_customer", "foreignKey": "teamId", "sourceKey": "id", "targetKey": "id", "onDelete": "SET NULL", "uiSchema": {"type": "array", "title": "负责客户", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 11),
  ('t_crm_teams', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 12),
  ('t_crm_teams', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 13),

  -- t_crm_teamMembers
  ('t_crm_teamMembers', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_teamMembers', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_teamMembers', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_teamMembers', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_teamMembers', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_teamMembers', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_teamMembers', 'team', 'belongsTo', 'm2o', '{"target": "t_crm_teams", "foreignKey": "teamId", "targetKey": "id", "uiSchema": {"type": "object", "title": "所属团队", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 7),
  ('t_crm_teamMembers', 'user', 'belongsTo', 'm2o', '{"target": "users", "foreignKey": "userId", "targetKey": "id", "uiSchema": {"type": "object", "title": "成员用户", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}}}', 8),
  ('t_crm_teamMembers', 'role', 'string', 'select', '{"allowNull": true, "field": "role", "defaultValue": "member", "uiSchema": {"type": "string", "title": "团队角色", "x-component": "Select", "enum": [{"value": "leader", "label": "团队负责人", "color": "blue"}, {"value": "member", "label": "团队成员", "color": "green"}]}}', 9),
  ('t_crm_teamMembers', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 10),
  ('t_crm_teamMembers', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 11),

  -- t_crm_customer
  ('t_crm_customer', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_customer', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_customer', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_customer', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_customer', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_customer', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_customer', 'assignee', 'belongsTo', 'm2o', '{"target": "users", "foreignKey": "assigneeId", "targetKey": "id", "uiSchema": {"type": "object", "title": "负责人", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}}}', 7),
  ('t_crm_customer', 'name', 'string', 'input', '{"allowNull": true, "field": "name", "uiSchema": {"type": "string", "title": "姓名", "x-component": "Input"}}', 8),
  ('t_crm_customer', 'phone', 'string', 'input', '{"allowNull": true, "field": "phone", "uiSchema": {"type": "string", "title": "手机号码", "x-component": "Input"}}', 9),
  ('t_crm_customer', 'addr', 'text', 'textarea', '{"allowNull": true, "field": "addr", "uiSchema": {"type": "string", "title": "地址", "x-component": "Input.TextArea"}}', 10),
  ('t_crm_customer', 'age', 'bigInt', 'integer', '{"allowNull": true, "field": "age", "uiSchema": {"type": "number", "title": "年龄", "x-component": "InputNumber"}}', 11),
  ('t_crm_customer', 'gender', 'string', 'radioGroup', '{"allowNull": true, "field": "gender", "uiSchema": {"type": "string", "title": "性别", "x-component": "Radio.Group", "enum": [{"value": "M", "label": "男", "color": "blue"}, {"value": "F", "label": "女", "color": "red"}, {"value": "Unknown", "label": "未知", "color": "default"}]}}', 12),
  ('t_crm_customer', 'state', 'string', 'select', '{"allowNull": true, "field": "state", "defaultValue": "sea", "uiSchema": {"type": "string", "title": "阶段状态", "x-component": "Select", "enum": [{"value": "sea", "label": "公海", "color": "blue"}, {"value": "assigned", "label": "已认领", "color": "magenta"}, {"value": "following", "label": "沟通中", "color": "green"}, {"value": "opportunity", "label": "高潜", "color": "lime"}, {"value": "customer", "label": "已购买", "color": "purple"}, {"value": "invalid", "label": "无效", "color": "default"}, {"value": "lost", "label": "流失", "color": "default"}]}}', 13),
  ('t_crm_customer', 'tags', 'belongsToMany', 'm2m', '{"target": "t_crm_tags", "through": "t_crm_customerTags", "foreignKey": "customer", "otherKey": "tag", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "顾客标签", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 14),
  ('t_crm_customer', 'records', 'hasMany', 'o2m', '{"target": "t_crm_customerRecords", "foreignKey": "customerId", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "沟通记录", "x-component": "AssociationField"}}', 15),
  ('t_crm_customer', 'orders', 'hasMany', 'o2m', '{"target": "t_crm_orders", "foreignKey": "customerId", "sourceKey": "id", "targetKey": "id", "onDelete": "SET NULL", "uiSchema": {"type": "array", "title": "订单列表", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 16),
  ('t_crm_customer', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 17),
  ('t_crm_customer', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 18),
  ('t_crm_customer', 'team', 'belongsTo', 'm2o', '{"target": "t_crm_teams", "foreignKey": "teamId", "targetKey": "id", "uiSchema": {"type": "object", "title": "跟进团队", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 19),
  ('t_crm_customer', 'contactMethods', 'hasMany', 'o2m', '{"target": "t_crm_contactMethods", "foreignKey": "customerId", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "联系方式", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 20),

  -- t_crm_contactMethods
  ('t_crm_contactMethods', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_contactMethods', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_contactMethods', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_contactMethods', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_contactMethods', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_contactMethods', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_contactMethods', 'customer', 'belongsTo', 'm2o', '{"target": "t_crm_customer", "foreignKey": "customerId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联顾客", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 7),
  ('t_crm_contactMethods', 'channel', 'string', 'select', '{"allowNull": false, "field": "channel", "uiSchema": {"type": "string", "title": "联系方式渠道", "x-component": "Select", "enum": [{"value": "phone", "label": "电话", "color": "blue"}, {"value": "wechat", "label": "微信/企业微信", "color": "green"}, {"value": "whatsapp", "label": "WhatsApp", "color": "green"}, {"value": "email", "label": "邮件", "color": "purple"}, {"value": "line", "label": "Line", "color": "green"}, {"value": "telegram", "label": "Telegram", "color": "blue"}, {"value": "other", "label": "其他", "color": "default"}]}}', 8),
  ('t_crm_contactMethods', 'account', 'string', 'input', '{"allowNull": false, "field": "account", "uiSchema": {"type": "string", "title": "联系方式账号", "x-component": "Input"}}', 9),
  ('t_crm_contactMethods', 'isPrimary', 'boolean', 'switch', '{"allowNull": true, "field": "isPrimary", "defaultValue": false, "uiSchema": {"type": "boolean", "title": "是否首选联系方式", "x-component": "Checkbox"}}', 10),
  ('t_crm_contactMethods', 'verified', 'boolean', 'switch', '{"allowNull": true, "field": "verified", "defaultValue": false, "uiSchema": {"type": "boolean", "title": "是否已验证", "x-component": "Checkbox"}}', 11),
  ('t_crm_contactMethods', 'records', 'hasMany', 'o2m', '{"target": "t_crm_customerRecords", "foreignKey": "contactMethodId", "sourceKey": "id", "targetKey": "id", "onDelete": "SET NULL", "uiSchema": {"type": "array", "title": "关联沟通记录", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 12),
  ('t_crm_contactMethods', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 13),
  ('t_crm_contactMethods', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 14),

  -- t_crm_customerRecords
  ('t_crm_customerRecords', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "记录ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_customerRecords', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_customerRecords', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_customerRecords', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_customerRecords', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_customerRecords', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_customerRecords', 'customer', 'belongsTo', 'm2o', '{"target": "t_crm_customer", "foreignKey": "customerId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联顾客", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 7),
  ('t_crm_customerRecords', 'contactMethod', 'belongsTo', 'm2o', '{"target": "t_crm_contactMethods", "foreignKey": "contactMethodId", "targetKey": "id", "uiSchema": {"type": "object", "title": "使用联系方式", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "account"}}}}', 8),
  ('t_crm_customerRecords', 'title', 'string', 'input', '{"allowNull": true, "field": "title", "uiSchema": {"type": "string", "title": "沟通主题", "x-component": "Input"}}', 9),
  ('t_crm_customerRecords', 'type', 'string', 'select', '{"allowNull": true, "field": "type", "defaultValue": "call", "uiSchema": {"type": "string", "title": "沟通方式", "x-component": "Select", "enum": [{"value": "call", "label": "电话沟通", "color": "blue"}, {"value": "meeting", "label": "当面拜访", "color": "magenta"}, {"value": "wechat", "label": "微信沟通", "color": "green"}, {"value": "email", "label": "邮件往来", "color": "purple"}, {"value": "other", "label": "其他", "color": "default"}]}}', 10),
  ('t_crm_customerRecords', 'content', 'text', 'textarea', '{"allowNull": true, "field": "content", "uiSchema": {"type": "string", "title": "沟通内容", "x-component": "Input.TextArea"}}', 11),
  ('t_crm_customerRecords', 'recordTime', 'datetimeTz', 'datetime', '{"field": "recordTime", "uiSchema": {"type": "datetime", "title": "沟通时间", "x-component": "DatePicker", "x-component-props": {"showTime": true}}}', 12),
  ('t_crm_customerRecords', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 13),
  ('t_crm_customerRecords', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 14),

  -- t_crm_tags
  ('t_crm_tags', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_tags', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_tags', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_tags', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_tags', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_tags', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_tags', 'dimension', 'string', 'input', '{"allowNull": true, "field": "dimension", "uiSchema": {"type": "string", "title": "标签维度", "x-component": "Input"}}', 7),
  ('t_crm_tags', 'tag', 'string', 'input', '{"allowNull": true, "field": "tag", "uiSchema": {"type": "string", "title": "标签名称", "x-component": "Input"}}', 8),
  ('t_crm_tags', 'state', 'string', 'select', '{"allowNull": true, "field": "state", "defaultValue": "0", "uiSchema": {"type": "string", "title": "标签状态", "x-component": "Select", "enum": [{"value": "0", "label": "正常", "color": "blue"}, {"value": "1", "label": "禁用", "color": "default"}]}}', 9),
  ('t_crm_tags', 'customers', 'belongsToMany', 'm2m', '{"target": "t_crm_customer", "through": "t_crm_customerTags", "foreignKey": "tag", "otherKey": "customer", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "关联顾客", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 10),
  ('t_crm_tags', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 11),
  ('t_crm_tags', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 12),

  -- t_crm_customerTags (Through Collection with surrogate id)
  ('t_crm_customerTags', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_customerTags', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_customerTags', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_customerTags', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_customerTags', 'customer', 'bigInt', 'integer', '{"primaryKey": false, "isForeignKey": true, "uiSchema": {"type": "number", "title": "顾客", "x-component": "InputNumber", "x-read-pretty": true}}', 5),
  ('t_crm_customerTags', 'tag', 'bigInt', 'integer', '{"primaryKey": false, "isForeignKey": true, "uiSchema": {"type": "number", "title": "标签", "x-component": "InputNumber", "x-read-pretty": true}}', 6),
  ('t_crm_customerTags', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 7),
  ('t_crm_customerTags', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 8),

  -- t_meta_spus
  ('t_meta_spus', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_meta_spus', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_meta_spus', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_meta_spus', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_meta_spus', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_meta_spus', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_meta_spus', 'productName', 'string', 'input', '{"allowNull": false, "field": "productName", "uiSchema": {"type": "string", "title": "产品名", "x-component": "Input"}}', 7),
  ('t_meta_spus', 'spec', 'string', 'input', '{"allowNull": true, "field": "spec", "uiSchema": {"type": "string", "title": "规格", "x-component": "Input"}}', 8),
  ('t_meta_spus', 'baseUnit', 'string', 'input', '{"allowNull": true, "field": "baseUnit", "uiSchema": {"type": "string", "title": "基础计量单位", "x-component": "Input"}}', 9),
  ('t_meta_spus', 'unitMeasureValue', 'float', 'number', '{"allowNull": false, "field": "unitMeasureValue", "uiSchema": {"type": "number", "title": "最小单元计量数量", "x-component": "InputNumber"}}', 10),
  ('t_meta_spus', 'unitMeasureUnit', 'string', 'input', '{"allowNull": true, "field": "unitMeasureUnit", "uiSchema": {"type": "string", "title": "最小单元计量单位", "x-component": "Input"}}', 11),
  ('t_meta_spus', 'spuDisplayName', 'string', 'input', '{"allowNull": true, "field": "spuDisplayName", "uiSchema": {"type": "string", "title": "SPU展示名", "x-component": "Input"}}', 12),
  ('t_meta_spus', 'skus', 'hasMany', 'o2m', '{"target": "t_meta_skus", "foreignKey": "spuId", "sourceKey": "id", "targetKey": "id", "onDelete": "SET NULL", "uiSchema": {"type": "array", "title": "规格列表(SKU)", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 13),
  ('t_meta_spus', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 14),
  ('t_meta_spus', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 15),

  -- t_meta_skus
  ('t_meta_skus', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_meta_skus', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_meta_skus', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_meta_skus', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_meta_skus', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_meta_skus', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_meta_skus', 'spu', 'belongsTo', 'm2o', '{"target": "t_meta_spus", "foreignKey": "spuId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联产品(SPU)", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "productName"}}}}', 7),
  ('t_meta_skus', 'packageQty', 'float', 'number', '{"allowNull": false, "field": "packageQty", "uiSchema": {"type": "number", "title": "包装内数量", "x-component": "InputNumber"}}', 8),
  ('t_meta_skus', 'saleUnit', 'string', 'input', '{"allowNull": true, "field": "saleUnit", "uiSchema": {"type": "string", "title": "销售单位", "x-component": "Input"}}', 9),
  ('t_meta_skus', 'skuDisplayName', 'text', 'textarea', '{"allowNull": false, "field": "skuDisplayName", "uiSchema": {"type": "string", "title": "SKU展示名", "x-component": "Input.TextArea"}}', 10),
  ('t_meta_skus', 'salePrice', 'float', 'number', '{"allowNull": false, "field": "salePrice", "uiSchema": {"type": "number", "title": "销售单价", "x-component": "InputNumber"}}', 11),
  ('t_meta_skus', 'orderItems', 'hasMany', 'o2m', '{"target": "t_crm_orderItems", "foreignKey": "skuId", "sourceKey": "id", "targetKey": "id", "onDelete": "SET NULL", "uiSchema": {"type": "array", "title": "销售明细", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 12),
  ('t_meta_skus', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 13),
  ('t_meta_skus', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 14),

  -- t_crm_orders
  ('t_crm_orders', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "订单ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_orders', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_orders', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_orders', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_orders', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_orders', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_orders', 'customer', 'belongsTo', 'm2o', '{"target": "t_crm_customer", "foreignKey": "customerId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联顾客", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 7),
  ('t_crm_orders', 'status', 'string', 'select', '{"allowNull": true, "field": "status", "defaultValue": "pending", "uiSchema": {"type": "string", "title": "订单状态", "x-component": "Select", "enum": [{"value": "pending", "label": "待支付", "color": "gold"}, {"value": "processing", "label": "处理中", "color": "blue"}, {"value": "shipped", "label": "已发货", "color": "purple"}, {"value": "completed", "label": "已完成", "color": "green"}, {"value": "cancelled", "label": "已取消", "color": "default"}]}}', 8),
  ('t_crm_orders', 'total', 'float', 'number', '{"allowNull": true, "field": "total", "uiSchema": {"type": "number", "title": "订单总金额", "x-component": "InputNumber"}}', 9),
  ('t_crm_orders', 'items', 'hasMany', 'o2m', '{"target": "t_crm_orderItems", "foreignKey": "orderId", "sourceKey": "id", "targetKey": "id", "onDelete": "SET NULL", "uiSchema": {"type": "array", "title": "订单明细", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 10),
  ('t_crm_orders', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 11),
  ('t_crm_orders', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 12),

  -- t_crm_orderItems
  ('t_crm_orderItems', 'id', 'snowflakeId', 'snowflakeId', '{"autoIncrement": false, "primaryKey": true, "allowNull": false, "field": "id", "uiSchema": {"type": "number", "title": "明细ID", "x-component": "InputNumber", "x-component-props": {"stringMode": true, "separator": "0.00", "step": "1"}, "x-validator": "integer"}}', 1),
  ('t_crm_orderItems', 'code', 'string', 'input', '{"allowNull": true, "field": "code", "uiSchema": {"type": "string", "title": "业务编码", "x-component": "Input", "x-read-pretty": true}}', 2),
  ('t_crm_orderItems', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 3),
  ('t_crm_orderItems', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 4),
  ('t_crm_orderItems', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 5),
  ('t_crm_orderItems', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 6),
  ('t_crm_orderItems', 'sku', 'belongsTo', 'm2o', '{"target": "t_meta_skus", "foreignKey": "skuId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联商品规格(SKU)", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "skuDisplayName"}}}}', 7),
  ('t_crm_orderItems', 'order', 'belongsTo', 'm2o', '{"target": "t_crm_orders", "foreignKey": "orderId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联订单", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "code"}}}}', 8),
  ('t_crm_orderItems', 'quantity', 'float', 'number', '{"allowNull": false, "field": "quantity", "uiSchema": {"type": "number", "title": "数量", "x-component": "InputNumber"}}', 9),
  ('t_crm_orderItems', 'unitPrice', 'float', 'number', '{"allowNull": false, "field": "unitPrice", "uiSchema": {"type": "number", "title": "单价", "x-component": "InputNumber"}}', 10),
  ('t_crm_orderItems', 'data1', 'text', 'textarea', '{"allowNull": true, "field": "data1", "uiSchema": {"type": "string", "title": "备注", "x-component": "Input.TextArea"}}', 11),
  ('t_crm_orderItems', 'data2', 'text', 'textarea', '{"allowNull": true, "field": "data2", "uiSchema": {"type": "string", "title": "其他", "x-component": "Input.TextArea"}}', 12)
) AS v(col_name, f_name, f_type, f_iface, opts, sort_val)
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fields')
ON CONFLICT ("collectionName", "name") DO UPDATE SET
  "type" = EXCLUDED."type",
  "interface" = EXCLUDED."interface",
  "options" = EXCLUDED."options",
  "sort" = EXCLUDED."sort";

-- Ensure all NULL sort values in fields table are populated to prevent plugin-field-sort error
UPDATE "fields" SET "sort" = sub.seq
FROM (
  SELECT key, ROW_NUMBER() OVER (ORDER BY "collectionName", name) as seq
  FROM "fields"
) sub
WHERE "fields".key = sub.key AND "fields"."sort" IS NULL;

-- Batch update primaryKey: true for all CRM/meta tables' primary key fields
UPDATE "fields"
SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || '{"primaryKey": true}'::jsonb)::json 
WHERE ("collectionName" IN ('t_crm_customer', 't_crm_contactMethods', 't_crm_customerRecords', 't_crm_tags', 't_crm_teams', 't_crm_teamMembers', 't_meta_spus', 't_meta_skus', 't_crm_orders', 't_crm_orderItems') AND "name" = 'id')
   OR ("collectionName" = 't_crm_customerTags' AND "name" = 'id');

-- =========================================================
-- 5. Business Triggers (Auto calculate order.total from items)
-- =========================================================
CREATE OR REPLACE FUNCTION fn_update_crm_order_total()
RETURNS TRIGGER AS $$
DECLARE
  v_order_id bigint;
BEGIN
  v_order_id := COALESCE(NEW."orderId", OLD."orderId");

  IF v_order_id IS NOT NULL THEN
    UPDATE "t_crm_orders"
    SET "total" = COALESCE((
      SELECT SUM("quantity" * "unitPrice") FROM "t_crm_orderItems" WHERE "orderId" = v_order_id
    ), 0)
    WHERE "id" = v_order_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_crm_order_total ON "t_crm_orderItems";
CREATE TRIGGER trg_update_crm_order_total
AFTER INSERT OR UPDATE OF "quantity", "unitPrice", "orderId" OR DELETE
ON "t_crm_orderItems"
FOR EACH ROW
EXECUTE FUNCTION fn_update_crm_order_total();
