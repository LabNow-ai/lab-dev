/*
  NocoBase current-schema bootstrap (PostgreSQL) - "public" schema
  - CRM tables prefixed with "t_crm_" in "public" schema
  - Sequences + DEFAULT nextval(...)
  - Includes NocoBase system metadata (categories, collections & fields) registration
*/

-- =========================================================
-- 1. Sequences
-- =========================================================
CREATE SEQUENCE IF NOT EXISTS "t_crm_contacts_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_tags_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_spus_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_skus_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_orders_id_seq";
CREATE SEQUENCE IF NOT EXISTS "t_crm_orderItems_id_seq";

-- =========================================================
-- 2. Main tables
-- =========================================================

CREATE TABLE IF NOT EXISTS "t_crm_contacts" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_contacts_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "phone" character varying(255),
  "age" bigint,
  "gender" character varying(255),
  "state" character varying(255) DEFAULT 'lead',
  "name" character varying(255),
  CONSTRAINT "t_crm_contacts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_tags" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_tags_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "tag" character varying(255),
  "state" character varying(255) DEFAULT 'custom',
  CONSTRAINT "t_crm_tags_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_spus" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_spus_id_seq'::regclass),
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
  CONSTRAINT "t_crm_spus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_skus" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_skus_id_seq'::regclass),
  "spuId" bigint,
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "packageQty" double precision NOT NULL,
  "saleUnit" character varying(255),
  "packageSpecDisplay" text NOT NULL,
  "salePrice" double precision NOT NULL,
  CONSTRAINT "t_crm_skus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_orders" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_orders_id_seq'::regclass),
  "fk_orders" bigint,
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "total" double precision,
  CONSTRAINT "t_crm_orders_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_orderItems" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_orderItems_id_seq"'::regclass),
  "fk_sku" bigint,
  "fk_order" bigint,
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "quantity" double precision NOT NULL,
  "unitPrice" double precision NOT NULL,
  CONSTRAINT "t_crm_orderItems_pkey" PRIMARY KEY ("id")
);

-- =========================================================
-- 3. Bind sequence ownership
-- =========================================================
ALTER SEQUENCE "t_crm_contacts_id_seq" OWNED BY "t_crm_contacts"."id";
ALTER SEQUENCE "t_crm_tags_id_seq" OWNED BY "t_crm_tags"."id";
ALTER SEQUENCE "t_crm_spus_id_seq" OWNED BY "t_crm_spus"."id";
ALTER SEQUENCE "t_crm_skus_id_seq" OWNED BY "t_crm_skus"."id";
ALTER SEQUENCE "t_crm_orders_id_seq" OWNED BY "t_crm_orders"."id";
ALTER SEQUENCE "t_crm_orderItems_id_seq" OWNED BY "t_crm_orderItems"."id";

-- =========================================================
-- 4. NocoBase System Metadata Registration (Batch Operations)
-- =========================================================

-- 4.1 Collection Category Registration ('CRM')
INSERT INTO "collectionCategories" ("id", "name", "color", "sort", "createdAt", "updatedAt")
SELECT (EXTRACT(EPOCH FROM NOW())::bigint * 1000), 'CRM', 'magenta', 1, NOW(), NOW()
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategories')
  AND NOT EXISTS (SELECT 1 FROM "collectionCategories" WHERE "name" = 'CRM');

INSERT INTO "collectionCategory" ("categoryId", "collectionName", "createdAt", "updatedAt")
SELECT c.id, col.name, NOW(), NOW()
FROM "collectionCategories" c
CROSS JOIN (VALUES ('t_crm_contacts'), ('t_crm_tags'), ('t_crm_spus'), ('t_crm_skus'), ('t_crm_orders'), ('t_crm_orderItems')) AS col(name)
WHERE c.name = 'CRM'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategory')
  AND NOT EXISTS (
    SELECT 1 FROM "collectionCategory" cc WHERE cc."categoryId" = c.id AND cc."collectionName" = col.name
  );

-- 4.2 Collections Registration & Target Key Configuration
-- Batch Update existing collections (post-dbsync)
UPDATE "collections" AS c
SET "title" = v.title,
    "options" = jsonb_build_object(
      'tableName', v.name,
      'timestamps', false,
      'autoGenId', false,
      'filterTargetKey', jsonb_build_array('id'),
      'from', 'dbsync',
      'underscored', false,
      'unavailableActions', jsonb_build_array()
    )::json
FROM (VALUES
  ('t_crm_contacts',   '联系人'),
  ('t_crm_tags',       '标签'),
  ('t_crm_spus',       '产品(SPU)'),
  ('t_crm_skus',       '商品规格(SKU)'),
  ('t_crm_orders',     '订单'),
  ('t_crm_orderItems', '订单明细')
) AS v(name, title)
WHERE c."name" = v.name;

-- Batch Insert missing collections (pre-dbsync fallback)
INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options")
SELECT
  'crm_' || v.name,
  v.name,
  v.title,
  false,
  false,
  jsonb_build_object(
    'tableName', v.name,
    'timestamps', false,
    'autoGenId', false,
    'filterTargetKey', jsonb_build_array('id'),
    'from', 'dbsync',
    'underscored', false,
    'unavailableActions', jsonb_build_array()
  )::json
FROM (VALUES
  ('t_crm_contacts',   '联系人'),
  ('t_crm_tags',       '标签'),
  ('t_crm_spus',       '产品(SPU)'),
  ('t_crm_skus',       '商品规格(SKU)'),
  ('t_crm_orders',     '订单'),
  ('t_crm_orderItems', '订单明细')
) AS v(name, title)
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
  AND NOT EXISTS (SELECT 1 FROM "collections" WHERE "name" = v.name);

-- 4.3 Fields Registration & Display Titles (Batch Insert & Update)

-- Batch Insert all fields into NocoBase fields table if not yet exist
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
  -- t_crm_contacts
  ('t_crm_contacts', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_contacts', 'name', 'string', 'input', '{"allowNull": true, "field": "name", "uiSchema": {"type": "string", "title": "姓名", "x-component": "Input"}}', 2),
  ('t_crm_contacts', 'phone', 'string', 'input', '{"allowNull": true, "field": "phone", "uiSchema": {"type": "string", "title": "手机号码", "x-component": "Input"}}', 3),
  ('t_crm_contacts', 'age', 'bigInt', 'integer', '{"allowNull": true, "field": "age", "uiSchema": {"type": "number", "title": "年龄", "x-component": "InputNumber"}}', 4),
  ('t_crm_contacts', 'gender', 'string', 'input', '{"allowNull": true, "field": "gender", "uiSchema": {"type": "string", "title": "性别", "x-component": "Input"}}', 5),
  ('t_crm_contacts', 'state', 'string', 'input', '{"allowNull": true, "field": "state", "uiSchema": {"type": "string", "title": "阶段状态", "x-component": "Input"}}', 6),
  ('t_crm_contacts', 'createdAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "createdAt", "uiSchema": {"type": "datetime", "title": "创建时间", "x-component": "DatePicker"}}', 7),
  ('t_crm_contacts', 'createdById', 'bigInt', 'integer', '{"allowNull": true, "field": "createdById", "uiSchema": {"type": "number", "title": "创建人ID", "x-component": "InputNumber"}}', 8),
  ('t_crm_contacts', 'updatedAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "updatedAt", "uiSchema": {"type": "datetime", "title": "更新时间", "x-component": "DatePicker"}}', 9),
  ('t_crm_contacts', 'updatedById', 'bigInt', 'integer', '{"allowNull": true, "field": "updatedById", "uiSchema": {"type": "number", "title": "更新人ID", "x-component": "InputNumber"}}', 10),
  -- t_crm_tags
  ('t_crm_tags', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_tags', 'tag', 'string', 'input', '{"allowNull": true, "field": "tag", "uiSchema": {"type": "string", "title": "标签名称", "x-component": "Input"}}', 2),
  ('t_crm_tags', 'state', 'string', 'input', '{"allowNull": true, "field": "state", "uiSchema": {"type": "string", "title": "标签状态", "x-component": "Input"}}', 3),
  ('t_crm_tags', 'createdAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "createdAt", "uiSchema": {"type": "datetime", "title": "创建时间", "x-component": "DatePicker"}}', 4),
  ('t_crm_tags', 'createdById', 'bigInt', 'integer', '{"allowNull": true, "field": "createdById", "uiSchema": {"type": "number", "title": "创建人ID", "x-component": "InputNumber"}}', 5),
  ('t_crm_tags', 'updatedAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "updatedAt", "uiSchema": {"type": "datetime", "title": "更新时间", "x-component": "DatePicker"}}', 6),
  ('t_crm_tags', 'updatedById', 'bigInt', 'integer', '{"allowNull": true, "field": "updatedById", "uiSchema": {"type": "number", "title": "更新人ID", "x-component": "InputNumber"}}', 7),
  -- t_crm_spus
  ('t_crm_spus', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_spus', 'productName', 'string', 'input', '{"allowNull": false, "field": "productName", "uiSchema": {"type": "string", "title": "药品名称/产品名", "x-component": "Input"}}', 2),
  ('t_crm_spus', 'dosageForm', 'string', 'input', '{"allowNull": true, "field": "dosageForm", "uiSchema": {"type": "string", "title": "剂型", "x-component": "Input"}}', 3),
  ('t_crm_spus', 'baseUnit', 'string', 'input', '{"allowNull": true, "field": "baseUnit", "uiSchema": {"type": "string", "title": "基本单位", "x-component": "Input"}}', 4),
  ('t_crm_spus', 'unitMeasureValue', 'float', 'number', '{"allowNull": false, "field": "unitMeasureValue", "uiSchema": {"type": "number", "title": "单剂量数值", "x-component": "InputNumber"}}', 5),
  ('t_crm_spus', 'unitMeasureUnit', 'string', 'input', '{"allowNull": true, "field": "unitMeasureUnit", "uiSchema": {"type": "string", "title": "单剂量单位", "x-component": "Input"}}', 6),
  ('t_crm_spus', 'unitSpecDisplay', 'string', 'input', '{"allowNull": true, "field": "unitSpecDisplay", "uiSchema": {"type": "string", "title": "规格显示名称", "x-component": "Input"}}', 7),
  ('t_crm_spus', 'createdAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "createdAt", "uiSchema": {"type": "datetime", "title": "创建时间", "x-component": "DatePicker"}}', 8),
  ('t_crm_spus', 'createdById', 'bigInt', 'integer', '{"allowNull": true, "field": "createdById", "uiSchema": {"type": "number", "title": "创建人ID", "x-component": "InputNumber"}}', 9),
  ('t_crm_spus', 'updatedAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "updatedAt", "uiSchema": {"type": "datetime", "title": "更新时间", "x-component": "DatePicker"}}', 10),
  ('t_crm_spus', 'updatedById', 'bigInt', 'integer', '{"allowNull": true, "field": "updatedById", "uiSchema": {"type": "number", "title": "更新人ID", "x-component": "InputNumber"}}', 11),
  -- t_crm_skus
  ('t_crm_skus', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_skus', 'spuId', 'bigInt', 'integer', '{"allowNull": true, "field": "spuId", "uiSchema": {"type": "number", "title": "关联SPU ID", "x-component": "InputNumber"}}', 2),
  ('t_crm_skus', 'packageQty', 'float', 'number', '{"allowNull": false, "field": "packageQty", "uiSchema": {"type": "number", "title": "包装内数量", "x-component": "InputNumber"}}', 3),
  ('t_crm_skus', 'saleUnit', 'string', 'input', '{"allowNull": true, "field": "saleUnit", "uiSchema": {"type": "string", "title": "销售单位", "x-component": "Input"}}', 4),
  ('t_crm_skus', 'packageSpecDisplay', 'text', 'textarea', '{"allowNull": false, "field": "packageSpecDisplay", "uiSchema": {"type": "string", "title": "包装规格说明", "x-component": "Input.TextArea"}}', 5),
  ('t_crm_skus', 'salePrice', 'float', 'number', '{"allowNull": false, "field": "salePrice", "uiSchema": {"type": "number", "title": "销售单价", "x-component": "InputNumber"}}', 6),
  ('t_crm_skus', 'createdAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "createdAt", "uiSchema": {"type": "datetime", "title": "创建时间", "x-component": "DatePicker"}}', 7),
  ('t_crm_skus', 'createdById', 'bigInt', 'integer', '{"allowNull": true, "field": "createdById", "uiSchema": {"type": "number", "title": "创建人ID", "x-component": "InputNumber"}}', 8),
  ('t_crm_skus', 'updatedAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "updatedAt", "uiSchema": {"type": "datetime", "title": "更新时间", "x-component": "DatePicker"}}', 9),
  ('t_crm_skus', 'updatedById', 'bigInt', 'integer', '{"allowNull": true, "field": "updatedById", "uiSchema": {"type": "number", "title": "更新人ID", "x-component": "InputNumber"}}', 10),
  -- t_crm_orders
  ('t_crm_orders', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "订单ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_orders', 'fk_orders', 'bigInt', 'integer', '{"allowNull": true, "field": "fk_orders", "uiSchema": {"type": "number", "title": "关联客户/联系人ID", "x-component": "InputNumber"}}', 2),
  ('t_crm_orders', 'total', 'float', 'number', '{"allowNull": true, "field": "total", "uiSchema": {"type": "number", "title": "订单总金额", "x-component": "InputNumber"}}', 3),
  ('t_crm_orders', 'createdAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "createdAt", "uiSchema": {"type": "datetime", "title": "创建时间", "x-component": "DatePicker"}}', 4),
  ('t_crm_orders', 'createdById', 'bigInt', 'integer', '{"allowNull": true, "field": "createdById", "uiSchema": {"type": "number", "title": "创建人ID", "x-component": "InputNumber"}}', 5),
  ('t_crm_orders', 'updatedAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "updatedAt", "uiSchema": {"type": "datetime", "title": "更新时间", "x-component": "DatePicker"}}', 6),
  ('t_crm_orders', 'updatedById', 'bigInt', 'integer', '{"allowNull": true, "field": "updatedById", "uiSchema": {"type": "number", "title": "更新人ID", "x-component": "InputNumber"}}', 7),
  -- t_crm_orderItems
  ('t_crm_orderItems', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "明细ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_orderItems', 'fk_sku', 'bigInt', 'integer', '{"allowNull": true, "field": "fk_sku", "uiSchema": {"type": "number", "title": "关联SKU ID", "x-component": "InputNumber"}}', 2),
  ('t_crm_orderItems', 'fk_order', 'bigInt', 'integer', '{"allowNull": true, "field": "fk_order", "uiSchema": {"type": "number", "title": "关联订单ID", "x-component": "InputNumber"}}', 3),
  ('t_crm_orderItems', 'quantity', 'float', 'number', '{"allowNull": false, "field": "quantity", "uiSchema": {"type": "number", "title": "数量", "x-component": "InputNumber"}}', 4),
  ('t_crm_orderItems', 'unitPrice', 'float', 'number', '{"allowNull": false, "field": "unitPrice", "uiSchema": {"type": "number", "title": "单价", "x-component": "InputNumber"}}', 5),
  ('t_crm_orderItems', 'createdAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "createdAt", "uiSchema": {"type": "datetime", "title": "创建时间", "x-component": "DatePicker"}}', 6),
  ('t_crm_orderItems', 'createdById', 'bigInt', 'integer', '{"allowNull": true, "field": "createdById", "uiSchema": {"type": "number", "title": "创建人ID", "x-component": "InputNumber"}}', 7),
  ('t_crm_orderItems', 'updatedAt', 'datetimeTz', 'datetime', '{"allowNull": true, "field": "updatedAt", "uiSchema": {"type": "datetime", "title": "更新时间", "x-component": "DatePicker"}}', 8),
  ('t_crm_orderItems', 'updatedById', 'bigInt', 'integer', '{"allowNull": true, "field": "updatedById", "uiSchema": {"type": "number", "title": "更新人ID", "x-component": "InputNumber"}}', 9)
) AS v(col_name, f_name, f_type, f_iface, opts, sort_val)
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fields')
  AND NOT EXISTS (SELECT 1 FROM "fields" WHERE "collectionName" = v.col_name AND "name" = v.f_name);

-- Ensure all NULL sort values in fields table are populated to prevent plugin-field-sort error
UPDATE "fields" SET "sort" = sub.seq
FROM (
  SELECT key, ROW_NUMBER() OVER (ORDER BY "collectionName", name) as seq
  FROM "fields"
) sub
WHERE "fields".key = sub.key AND "fields"."sort" IS NULL;

-- Batch Update primaryKey: true for all CRM tables' id field
UPDATE "fields"
SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || '{"primaryKey": true}'::jsonb)::json 
WHERE "collectionName" IN ('t_crm_contacts', 't_crm_tags', 't_crm_spus', 't_crm_skus', 't_crm_orders', 't_crm_orderItems') AND "name" = 'id';

-- Batch Update field display titles for existing fields
UPDATE "fields" AS f
SET "options" = (
  COALESCE("options"::jsonb, '{}'::jsonb) || jsonb_build_object(
    'uiSchema',
    COALESCE(("options"::jsonb)->'uiSchema', '{}'::jsonb) || jsonb_build_object('title', v.title)
  )
)::json
FROM (VALUES
  -- t_crm_contacts
  ('t_crm_contacts', 'id', 'ID'),
  ('t_crm_contacts', 'name', '姓名'),
  ('t_crm_contacts', 'phone', '手机号码'),
  ('t_crm_contacts', 'age', '年龄'),
  ('t_crm_contacts', 'gender', '性别'),
  ('t_crm_contacts', 'state', '阶段状态'),
  ('t_crm_contacts', 'createdAt', '创建时间'),
  ('t_crm_contacts', 'createdById', '创建人ID'),
  ('t_crm_contacts', 'updatedAt', '更新时间'),
  ('t_crm_contacts', 'updatedById', '更新人ID'),
  -- t_crm_tags
  ('t_crm_tags', 'id', 'ID'),
  ('t_crm_tags', 'tag', '标签名称'),
  ('t_crm_tags', 'state', '标签类型/状态'),
  ('t_crm_tags', 'createdAt', '创建时间'),
  ('t_crm_tags', 'createdById', '创建人ID'),
  ('t_crm_tags', 'updatedAt', '更新时间'),
  ('t_crm_tags', 'updatedById', '更新人ID'),
  -- t_crm_spus
  ('t_crm_spus', 'id', 'ID'),
  ('t_crm_spus', 'productName', '药品名称/产品名'),
  ('t_crm_spus', 'dosageForm', '剂型'),
  ('t_crm_spus', 'baseUnit', '基本单位'),
  ('t_crm_spus', 'unitMeasureValue', '单剂量数值'),
  ('t_crm_spus', 'unitMeasureUnit', '单剂量单位'),
  ('t_crm_spus', 'unitSpecDisplay', '规格显示名称'),
  ('t_crm_spus', 'createdAt', '创建时间'),
  ('t_crm_spus', 'createdById', '创建人ID'),
  ('t_crm_spus', 'updatedAt', '更新时间'),
  ('t_crm_spus', 'updatedById', '更新人ID'),
  -- t_crm_skus
  ('t_crm_skus', 'id', 'ID'),
  ('t_crm_skus', 'spuId', '关联SPU ID'),
  ('t_crm_skus', 'packageQty', '包装内数量'),
  ('t_crm_skus', 'saleUnit', '销售单位'),
  ('t_crm_skus', 'packageSpecDisplay', '包装规格说明'),
  ('t_crm_skus', 'salePrice', '销售单价'),
  ('t_crm_skus', 'createdAt', '创建时间'),
  ('t_crm_skus', 'createdById', '创建人ID'),
  ('t_crm_skus', 'updatedAt', '更新时间'),
  ('t_crm_skus', 'updatedById', '更新人ID'),
  -- t_crm_orders
  ('t_crm_orders', 'id', '订单ID'),
  ('t_crm_orders', 'fk_orders', '关联客户/联系人ID'),
  ('t_crm_orders', 'total', '订单总金额'),
  ('t_crm_orders', 'createdAt', '创建时间'),
  ('t_crm_orders', 'createdById', '创建人ID'),
  ('t_crm_orders', 'updatedAt', '更新时间'),
  ('t_crm_orders', 'updatedById', '更新人ID'),
  -- t_crm_orderItems
  ('t_crm_orderItems', 'id', '明细ID'),
  ('t_crm_orderItems', 'fk_sku', '关联SKU ID'),
  ('t_crm_orderItems', 'fk_order', '关联订单ID'),
  ('t_crm_orderItems', 'quantity', '数量'),
  ('t_crm_orderItems', 'unitPrice', '单价'),
  ('t_crm_orderItems', 'createdAt', '创建时间'),
  ('t_crm_orderItems', 'createdById', '创建人ID'),
  ('t_crm_orderItems', 'updatedAt', '更新时间'),
  ('t_crm_orderItems', 'updatedById', '更新人ID')
) AS v(col_name, f_name, title)
WHERE f."collectionName" = v.col_name AND f."name" = v.f_name;
