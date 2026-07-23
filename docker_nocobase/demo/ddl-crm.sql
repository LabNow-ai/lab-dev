/*
  NocoBase current-schema bootstrap (PostgreSQL) - "public" schema
  - based on current uploaded field JSON
  - only current tables in "public" schema
  - no foreign keys / no extra constraints except primary keys
  - id uses explicit sequence + nextval(...) for better NocoBase recognition
  - Includes NocoBase system metadata (collections & fields) registration
*/

-- =========================================================
-- 1. Sequences
-- =========================================================
CREATE SEQUENCE IF NOT EXISTS "contacts_id_seq";
CREATE SEQUENCE IF NOT EXISTS "tags_id_seq";
CREATE SEQUENCE IF NOT EXISTS "spus_id_seq";
CREATE SEQUENCE IF NOT EXISTS "skus_id_seq";
CREATE SEQUENCE IF NOT EXISTS "orders_id_seq";
CREATE SEQUENCE IF NOT EXISTS "order_item_id_seq";

-- =========================================================
-- 2. Main tables
-- =========================================================

CREATE TABLE IF NOT EXISTS "contacts" (
  "id" bigint NOT NULL DEFAULT nextval('contacts_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "phone" character varying(255),
  "age" bigint,
  "gender" character varying(255),
  "state" character varying(255) DEFAULT 'lead',
  "name" character varying(255),
  CONSTRAINT "contacts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "tags" (
  "id" bigint NOT NULL DEFAULT nextval('tags_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "tag" character varying(255),
  "state" character varying(255) DEFAULT 'custom',
  CONSTRAINT "tags_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "spus" (
  "id" bigint NOT NULL DEFAULT nextval('spus_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "productName" character varying(255) NOT NULL,
  "dosageForm" character varying(255),
  "baseUnit" character varying(255),
  "unitMeasureValue" double precision NOT NULL,
  "unitMeasureUnit" character varying(255),
  "unitSpecDisplay" character varying(255),
  CONSTRAINT "spus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "skus" (
  "id" bigint NOT NULL DEFAULT nextval('skus_id_seq'::regclass),
  "spuId" bigint,
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "packageQty" double precision NOT NULL,
  "saleUnit" character varying(255),
  "packageSpecDisplay" text NOT NULL,
  "salePrice" double precision NOT NULL,
  CONSTRAINT "skus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "orders" (
  "id" bigint NOT NULL DEFAULT nextval('orders_id_seq'::regclass),
  "fk_orders" bigint,
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "total" double precision,
  CONSTRAINT "orders_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "order_item" (
  "id" bigint NOT NULL DEFAULT nextval('order_item_id_seq'::regclass),
  "fk_sku" bigint,
  "fk_order" bigint,
  "f_1v0rw7p0jjg" bigint,
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "quantity" double precision NOT NULL,
  "unitPrice" double precision NOT NULL,
  CONSTRAINT "order_item_pkey" PRIMARY KEY ("id")
);

-- =========================================================
-- 3. Bind sequence ownership
-- =========================================================
ALTER SEQUENCE "contacts_id_seq" OWNED BY "contacts"."id";
ALTER SEQUENCE "tags_id_seq" OWNED BY "tags"."id";
ALTER SEQUENCE "spus_id_seq" OWNED BY "spus"."id";
ALTER SEQUENCE "skus_id_seq" OWNED BY "skus"."id";
ALTER SEQUENCE "orders_id_seq" OWNED BY "orders"."id";
ALTER SEQUENCE "order_item_id_seq" OWNED BY "order_item"."id";

-- =========================================================
-- 4. NocoBase System Metadata (Category, Collections & Fields) Registration
-- =========================================================

-- ---------------------------------------------------------
-- 4.1 Collection Category Registration ('CRM')
-- ---------------------------------------------------------
-- Ensure category 'CRM' exists in NocoBase
INSERT INTO "collectionCategories" ("id", "name", "color", "sort", "createdAt", "updatedAt")
SELECT (EXTRACT(EPOCH FROM NOW())::bigint * 1000), 'CRM', 'magenta', 1, NOW(), NOW()
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategories')
  AND NOT EXISTS (SELECT 1 FROM "collectionCategories" WHERE "name" = 'CRM');

-- Link CRM tables to category 'CRM' in NocoBase
INSERT INTO "collectionCategory" ("categoryId", "collectionName", "createdAt", "updatedAt")
SELECT c.id, col.name, NOW(), NOW()
FROM "collectionCategories" c
CROSS JOIN (VALUES ('contacts'), ('tags'), ('spus'), ('skus'), ('orders'), ('order_item')) AS col(name)
WHERE c.name = 'CRM'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategory')
  AND NOT EXISTS (
    SELECT 1 FROM "collectionCategory" cc WHERE cc."categoryId" = c.id AND cc."collectionName" = col.name
  );

-- ---------------------------------------------------------
-- 4.2 Collections (Table Display Names)
-- ---------------------------------------------------------

-- Update titles if collection entries exist (e.g., synced via NocoBase Data Source Manager)
UPDATE "collections" SET "title" = '联系人' WHERE "name" = 'contacts';
UPDATE "collections" SET "title" = '标签' WHERE "name" = 'tags';
UPDATE "collections" SET "title" = '产品(SPU)' WHERE "name" = 'spus';
UPDATE "collections" SET "title" = '商品规格(SKU)' WHERE "name" = 'skus';
UPDATE "collections" SET "title" = '订单' WHERE "name" = 'orders';
UPDATE "collections" SET "title" = '订单明细' WHERE "name" = 'order_item';

-- Insert collection entries if not yet exist (Pre-dbsync fallback)
INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT 'crm_contacts', 'contacts', '联系人', false, false, '{"tableName":"contacts","timestamps":false,"autoGenId":false,"filterTargetKey":"id","from":"dbsync","underscored":false}'::json
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = 'contacts');

INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT 'crm_tags', 'tags', '标签', false, false, '{"tableName":"tags","timestamps":false,"autoGenId":false,"filterTargetKey":"id","from":"dbsync","underscored":false}'::json
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = 'tags');

INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT 'crm_spus', 'spus', '产品(SPU)', false, false, '{"tableName":"spus","timestamps":false,"autoGenId":false,"filterTargetKey":"id","from":"dbsync","underscored":false}'::json
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = 'spus');

INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT 'crm_skus', 'skus', '商品规格(SKU)', false, false, '{"tableName":"skus","timestamps":false,"autoGenId":false,"filterTargetKey":"id","from":"dbsync","underscored":false}'::json
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = 'skus');

INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT 'crm_orders', 'orders', '订单', false, false, '{"tableName":"orders","timestamps":false,"autoGenId":false,"filterTargetKey":"id","from":"dbsync","underscored":false}'::json
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = 'orders');

INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT 'crm_order_item', 'order_item', '订单明细', false, false, '{"tableName":"order_item","timestamps":false,"autoGenId":false,"filterTargetKey":"id","from":"dbsync","underscored":false}'::json
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = 'order_item');

-- ---------------------------------------------------------
-- 4.3 Fields Display Names (options -> uiSchema -> title)
-- ---------------------------------------------------------
-- Safely merge/update title inside fields.options (json type) -> uiSchema -> title

-- contacts
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', 'ID')))::json WHERE "collectionName" = 'contacts' AND "name" = 'id';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建时间')))::json WHERE "collectionName" = 'contacts' AND "name" = 'createdAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建人ID')))::json WHERE "collectionName" = 'contacts' AND "name" = 'createdById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新时间')))::json WHERE "collectionName" = 'contacts' AND "name" = 'updatedAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新人ID')))::json WHERE "collectionName" = 'contacts' AND "name" = 'updatedById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '手机号码')))::json WHERE "collectionName" = 'contacts' AND "name" = 'phone';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '年龄')))::json WHERE "collectionName" = 'contacts' AND "name" = 'age';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '性别')))::json WHERE "collectionName" = 'contacts' AND "name" = 'gender';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '阶段状态')))::json WHERE "collectionName" = 'contacts' AND "name" = 'state';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '姓名')))::json WHERE "collectionName" = 'contacts' AND "name" = 'name';

-- tags
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', 'ID')))::json WHERE "collectionName" = 'tags' AND "name" = 'id';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建时间')))::json WHERE "collectionName" = 'tags' AND "name" = 'createdAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建人ID')))::json WHERE "collectionName" = 'tags' AND "name" = 'createdById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新时间')))::json WHERE "collectionName" = 'tags' AND "name" = 'updatedAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新人ID')))::json WHERE "collectionName" = 'tags' AND "name" = 'updatedById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '标签名称')))::json WHERE "collectionName" = 'tags' AND "name" = 'tag';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '标签类型/状态')))::json WHERE "collectionName" = 'tags' AND "name" = 'state';

-- spus
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', 'ID')))::json WHERE "collectionName" = 'spus' AND "name" = 'id';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建时间')))::json WHERE "collectionName" = 'spus' AND "name" = 'createdAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建人ID')))::json WHERE "collectionName" = 'spus' AND "name" = 'createdById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新时间')))::json WHERE "collectionName" = 'spus' AND "name" = 'updatedAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新人ID')))::json WHERE "collectionName" = 'spus' AND "name" = 'updatedById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '药品名称/产品名')))::json WHERE "collectionName" = 'spus' AND "name" = 'productName';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '剂型')))::json WHERE "collectionName" = 'spus' AND "name" = 'dosageForm';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '基本单位')))::json WHERE "collectionName" = 'spus' AND "name" = 'baseUnit';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '单剂量数值')))::json WHERE "collectionName" = 'spus' AND "name" = 'unitMeasureValue';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '单剂量单位')))::json WHERE "collectionName" = 'spus' AND "name" = 'unitMeasureUnit';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '规格显示名称')))::json WHERE "collectionName" = 'spus' AND "name" = 'unitSpecDisplay';

-- skus
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', 'ID')))::json WHERE "collectionName" = 'skus' AND "name" = 'id';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '关联SPU ID')))::json WHERE "collectionName" = 'skus' AND "name" = 'spuId';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建时间')))::json WHERE "collectionName" = 'skus' AND "name" = 'createdAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建人ID')))::json WHERE "collectionName" = 'skus' AND "name" = 'createdById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新时间')))::json WHERE "collectionName" = 'skus' AND "name" = 'updatedAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新人ID')))::json WHERE "collectionName" = 'skus' AND "name" = 'updatedById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '包装内数量')))::json WHERE "collectionName" = 'skus' AND "name" = 'packageQty';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '销售单位')))::json WHERE "collectionName" = 'skus' AND "name" = 'saleUnit';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '包装规格说明')))::json WHERE "collectionName" = 'skus' AND "name" = 'packageSpecDisplay';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '销售单价')))::json WHERE "collectionName" = 'skus' AND "name" = 'salePrice';

-- orders
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '订单ID')))::json WHERE "collectionName" = 'orders' AND "name" = 'id';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '关联客户/联系人ID')))::json WHERE "collectionName" = 'orders' AND "name" = 'fk_orders';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建时间')))::json WHERE "collectionName" = 'orders' AND "name" = 'createdAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建人ID')))::json WHERE "collectionName" = 'orders' AND "name" = 'createdById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新时间')))::json WHERE "collectionName" = 'orders' AND "name" = 'updatedAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新人ID')))::json WHERE "collectionName" = 'orders' AND "name" = 'updatedById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '订单总金额')))::json WHERE "collectionName" = 'orders' AND "name" = 'total';

-- order_item
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '明细ID')))::json WHERE "collectionName" = 'order_item' AND "name" = 'id';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '关联SKU ID')))::json WHERE "collectionName" = 'order_item' AND "name" = 'fk_sku';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '关联订单ID')))::json WHERE "collectionName" = 'order_item' AND "name" = 'fk_order';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '自定义关联项')))::json WHERE "collectionName" = 'order_item' AND "name" = 'f_1v0rw7p0jjg';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建时间')))::json WHERE "collectionName" = 'order_item' AND "name" = 'createdAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '创建人ID')))::json WHERE "collectionName" = 'order_item' AND "name" = 'createdById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新时间')))::json WHERE "collectionName" = 'order_item' AND "name" = 'updatedAt';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '更新人ID')))::json WHERE "collectionName" = 'order_item' AND "name" = 'updatedById';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '数量')))::json WHERE "collectionName" = 'order_item' AND "name" = 'quantity';
UPDATE "fields" SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object('uiSchema', COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', '单价')))::json WHERE "collectionName" = 'order_item' AND "name" = 'unitPrice';
