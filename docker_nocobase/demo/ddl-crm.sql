/*
  NocoBase fresh-database bootstrap (PostgreSQL) - "public" schema
  - Standalone initial DDL for CRM tables (prefixed with "t_crm_")
  - Sequence + DEFAULT nextval(...)
  - Audit fields (id, createdAt, createdById, updatedAt, updatedById) placed immediately after id
  - Built-in NocoBase metadata registration (categories, collections & fields)
  - Built-in createdAt, createdBy, updatedAt, updatedBy field interfaces & sort order
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
-- 2. Main tables (Audit columns placed immediately after id)
-- =========================================================

CREATE TABLE IF NOT EXISTS "t_crm_contacts" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_contacts_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "name" character varying(255),
  "phone" character varying(255),
  "age" bigint,
  "gender" character varying(255),
  "state" character varying(255) DEFAULT 'lead',
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
  "spec" character varying(255),
  "baseUnit" character varying(255),
  "unitMeasureValue" double precision NOT NULL,
  "unitMeasureUnit" character varying(255),
  "unitSpecDisplay" character varying(255),
  CONSTRAINT "t_crm_spus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_skus" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_skus_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "spuId" bigint,
  "packageQty" double precision NOT NULL,
  "saleUnit" character varying(255),
  "packageSpecDisplay" text NOT NULL,
  "salePrice" double precision NOT NULL,
  CONSTRAINT "t_crm_skus_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_orders" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_orders_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "fk_orders" bigint,
  "total" double precision,
  CONSTRAINT "t_crm_orders_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_orderItems" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_orderItems_id_seq"'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "fk_sku" bigint,
  "fk_order" bigint,
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

-- 4.3 Fields Registration & Display Titles (Audit fields immediately after id)
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
  ('t_crm_contacts', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_contacts', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_contacts', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_contacts', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_contacts', 'name', 'string', 'input', '{"allowNull": true, "field": "name", "uiSchema": {"type": "string", "title": "姓名", "x-component": "Input"}}', 6),
  ('t_crm_contacts', 'phone', 'string', 'input', '{"allowNull": true, "field": "phone", "uiSchema": {"type": "string", "title": "手机号码", "x-component": "Input"}}', 7),
  ('t_crm_contacts', 'age', 'bigInt', 'integer', '{"allowNull": true, "field": "age", "uiSchema": {"type": "number", "title": "年龄", "x-component": "InputNumber"}}', 8),
  ('t_crm_contacts', 'gender', 'string', 'input', '{"allowNull": true, "field": "gender", "uiSchema": {"type": "string", "title": "性别", "x-component": "Input"}}', 9),
  ('t_crm_contacts', 'state', 'string', 'input', '{"allowNull": true, "field": "state", "uiSchema": {"type": "string", "title": "阶段状态", "x-component": "Input"}}', 10),

  -- t_crm_tags
  ('t_crm_tags', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_tags', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_tags', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_tags', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_tags', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_tags', 'tag', 'string', 'input', '{"allowNull": true, "field": "tag", "uiSchema": {"type": "string", "title": "标签名称", "x-component": "Input"}}', 6),
  ('t_crm_tags', 'state', 'string', 'input', '{"allowNull": true, "field": "state", "uiSchema": {"type": "string", "title": "标签状态", "x-component": "Input"}}', 7),

  -- t_crm_spus
  ('t_crm_spus', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_spus', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_spus', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_spus', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_spus', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_spus', 'productName', 'string', 'input', '{"allowNull": false, "field": "productName", "uiSchema": {"type": "string", "title": "药品名称/产品名", "x-component": "Input"}}', 6),
  ('t_crm_spus', 'spec', 'string', 'input', '{"allowNull": true, "field": "spec", "uiSchema": {"type": "string", "title": "规格", "x-component": "Input"}}', 7),
  ('t_crm_spus', 'baseUnit', 'string', 'input', '{"allowNull": true, "field": "baseUnit", "uiSchema": {"type": "string", "title": "基本单位", "x-component": "Input"}}', 8),
  ('t_crm_spus', 'unitMeasureValue', 'float', 'number', '{"allowNull": false, "field": "unitMeasureValue", "uiSchema": {"type": "number", "title": "单剂量数值", "x-component": "InputNumber"}}', 9),
  ('t_crm_spus', 'unitMeasureUnit', 'string', 'input', '{"allowNull": true, "field": "unitMeasureUnit", "uiSchema": {"type": "string", "title": "单剂量单位", "x-component": "Input"}}', 10),
  ('t_crm_spus', 'unitSpecDisplay', 'string', 'input', '{"allowNull": true, "field": "unitSpecDisplay", "uiSchema": {"type": "string", "title": "规格显示名称", "x-component": "Input"}}', 11),

  -- t_crm_skus
  ('t_crm_skus', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_skus', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_skus', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_skus', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_skus', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_skus', 'spuId', 'bigInt', 'integer', '{"allowNull": true, "field": "spuId", "uiSchema": {"type": "number", "title": "关联SPU ID", "x-component": "InputNumber"}}', 6),
  ('t_crm_skus', 'packageQty', 'float', 'number', '{"allowNull": false, "field": "packageQty", "uiSchema": {"type": "number", "title": "包装内数量", "x-component": "InputNumber"}}', 7),
  ('t_crm_skus', 'saleUnit', 'string', 'input', '{"allowNull": true, "field": "saleUnit", "uiSchema": {"type": "string", "title": "销售单位", "x-component": "Input"}}', 8),
  ('t_crm_skus', 'packageSpecDisplay', 'text', 'textarea', '{"allowNull": false, "field": "packageSpecDisplay", "uiSchema": {"type": "string", "title": "包装规格说明", "x-component": "Input.TextArea"}}', 9),
  ('t_crm_skus', 'salePrice', 'float', 'number', '{"allowNull": false, "field": "salePrice", "uiSchema": {"type": "number", "title": "销售单价", "x-component": "InputNumber"}}', 10),

  -- t_crm_orders
  ('t_crm_orders', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "订单ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_orders', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_orders', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_orders', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_orders', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_orders', 'fk_orders', 'bigInt', 'integer', '{"allowNull": true, "field": "fk_orders", "uiSchema": {"type": "number", "title": "关联客户/联系人ID", "x-component": "InputNumber"}}', 6),
  ('t_crm_orders', 'total', 'float', 'number', '{"allowNull": true, "field": "total", "uiSchema": {"type": "number", "title": "订单总金额", "x-component": "InputNumber"}}', 7),

  -- t_crm_orderItems
  ('t_crm_orderItems', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "明细ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_orderItems', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_orderItems', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_orderItems', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_orderItems', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_orderItems', 'fk_sku', 'bigInt', 'integer', '{"allowNull": true, "field": "fk_sku", "uiSchema": {"type": "number", "title": "关联SKU ID", "x-component": "InputNumber"}}', 6),
  ('t_crm_orderItems', 'fk_order', 'bigInt', 'integer', '{"allowNull": true, "field": "fk_order", "uiSchema": {"type": "number", "title": "关联订单ID", "x-component": "InputNumber"}}', 7),
  ('t_crm_orderItems', 'quantity', 'float', 'number', '{"allowNull": false, "field": "quantity", "uiSchema": {"type": "number", "title": "数量", "x-component": "InputNumber"}}', 8),
  ('t_crm_orderItems', 'unitPrice', 'float', 'number', '{"allowNull": false, "field": "unitPrice", "uiSchema": {"type": "number", "title": "单价", "x-component": "InputNumber"}}', 9)
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
