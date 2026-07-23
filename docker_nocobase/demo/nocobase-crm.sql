/*
  NocoBase fresh-database bootstrap (PostgreSQL) - "public" schema
  - Standalone initial DDL for CRM tables (prefixed with "t_crm_")
  - Sequence + DEFAULT nextval(...)
  - Physical foreign key constraints, M2M junction table (t_crm_contactTags) & O2M table (t_crm_contactRecords)
  - Built-in NocoBase metadata registration (categories, collections & fields)
  - Association metadata (m2o, m2m, o2m / belongsTo, belongsToMany, hasMany)
  - Collection sort numbers starting from 101
  - Composite primary key & filterTargetKey configuration for junction table (t_crm_contactTags)
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
CREATE SEQUENCE IF NOT EXISTS "t_crm_contactRecords_id_seq";

-- =========================================================
-- 2. Main tables (Audit columns placed immediately after id)
-- =========================================================

CREATE TABLE IF NOT EXISTS "t_crm_contacts" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_contacts_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "assigneeId" bigint,
  "name" character varying(255),
  "phone" character varying(255),
  "age" bigint,
  "gender" character varying(255),
  "state" character varying(255) DEFAULT 'sea',
  CONSTRAINT "t_crm_contacts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "t_crm_tags" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_tags_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "tag" character varying(255),
  "state" character varying(255) DEFAULT '0',
  CONSTRAINT "t_crm_tags_pkey" PRIMARY KEY ("id")
);

-- Many-to-Many Junction Table between t_crm_contacts and t_crm_tags
CREATE TABLE IF NOT EXISTS "t_crm_contactTags" (
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "contact" bigint NOT NULL,
  "tag" bigint NOT NULL,
  CONSTRAINT "t_crm_contactTags_pkey" PRIMARY KEY ("contact", "tag"),
  CONSTRAINT "t_crm_contactTags_contact_fkey" FOREIGN KEY ("contact") REFERENCES "t_crm_contacts"("id") ON DELETE CASCADE,
  CONSTRAINT "t_crm_contactTags_tag_fkey" FOREIGN KEY ("tag") REFERENCES "t_crm_tags"("id") ON DELETE CASCADE
);

-- One-to-Many Table for Contact Communication Records
CREATE TABLE IF NOT EXISTS "t_crm_contactRecords" (
  "id" bigint NOT NULL DEFAULT nextval('"t_crm_contactRecords_id_seq"'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "contactId" bigint NOT NULL,
  "title" character varying(255),
  "type" character varying(255) DEFAULT 'call',
  "content" text,
  "recordTime" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "t_crm_contactRecords_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_contactRecords_contactId_fkey" FOREIGN KEY ("contactId") REFERENCES "t_crm_contacts"("id") ON DELETE CASCADE
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
  CONSTRAINT "t_crm_skus_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_skus_spuId_fkey" FOREIGN KEY ("spuId") REFERENCES "t_crm_spus"("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "t_crm_orders" (
  "id" bigint NOT NULL DEFAULT nextval('t_crm_orders_id_seq'::regclass),
  "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdById" bigint,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" bigint,
  "fk_orders" bigint,
  "total" double precision,
  CONSTRAINT "t_crm_orders_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_orders_fk_orders_fkey" FOREIGN KEY ("fk_orders") REFERENCES "t_crm_contacts"("id") ON DELETE SET NULL
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
  CONSTRAINT "t_crm_orderItems_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "t_crm_orderItems_fk_sku_fkey" FOREIGN KEY ("fk_sku") REFERENCES "t_crm_skus"("id") ON DELETE SET NULL,
  CONSTRAINT "t_crm_orderItems_fk_order_fkey" FOREIGN KEY ("fk_order") REFERENCES "t_crm_orders"("id") ON DELETE CASCADE
);

-- =========================================================
-- 3. Bind sequence ownership & indexes
-- =========================================================
ALTER SEQUENCE "t_crm_contacts_id_seq" OWNED BY "t_crm_contacts"."id";
ALTER SEQUENCE "t_crm_tags_id_seq" OWNED BY "t_crm_tags"."id";
ALTER SEQUENCE "t_crm_spus_id_seq" OWNED BY "t_crm_spus"."id";
ALTER SEQUENCE "t_crm_skus_id_seq" OWNED BY "t_crm_skus"."id";
ALTER SEQUENCE "t_crm_orders_id_seq" OWNED BY "t_crm_orders"."id";
ALTER SEQUENCE "t_crm_orderItems_id_seq" OWNED BY "t_crm_orderItems"."id";
ALTER SEQUENCE "t_crm_contactRecords_id_seq" OWNED BY "t_crm_contactRecords"."id";

CREATE INDEX IF NOT EXISTS "t_crm_contacts_assignee_id_idx" ON "t_crm_contacts" ("assigneeId");
CREATE INDEX IF NOT EXISTS "t_crm_contactRecords_contact_id_idx" ON "t_crm_contactRecords" ("contactId");

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
CROSS JOIN (VALUES ('t_crm_contacts'), ('t_crm_tags'), ('t_crm_contactTags'), ('t_crm_contactRecords'), ('t_crm_spus'), ('t_crm_skus'), ('t_crm_orders'), ('t_crm_orderItems')) AS col(name)
WHERE c.name = 'CRM'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collectionCategory')
  AND NOT EXISTS (
    SELECT 1 FROM "collectionCategory" cc WHERE cc."categoryId" = c.id AND cc."collectionName" = col.name
  );

-- 4.2 Collections Registration & Target Key Configuration (sort starting from 101)
INSERT INTO "collections" ("key", "name", "title", "inherit", "hidden", "options", "sort")
SELECT
  'crm_' || v.name,
  v.name,
  v.title,
  false,
  false,
  v.opts::json,
  v.sort_val
FROM (VALUES
	('t_crm_tags',           '标签',            100, '{"tableName": "t_crm_tags", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "tag", "unavailableActions": []}'),
	('t_crm_contacts',       '联系人',          110, '{"tableName": "t_crm_contacts", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "name", "unavailableActions": []}'),
  ('t_crm_contactTags',    '客户标签',				111, '{"timestamps": true, "autoGenId": false, "autoCreate": true, "isThrough": true, "sortable": false, "filterTargetKey": ["contact", "tag"]}'),
	('t_crm_contactRecords', '客户沟通记录',		112, '{"tableName": "t_crm_contactRecords", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "title", "unavailableActions": []}'),
	('t_crm_spus',           '产品(SPU)',				121, '{"tableName": "t_crm_spus", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "productName", "unavailableActions": []}'),
	('t_crm_skus',           '商品规格(SKU)',		122, '{"tableName": "t_crm_skus", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "packageSpecDisplay", "unavailableActions": []}'),
	('t_crm_orders',         '订单',						131, '{"tableName": "t_crm_orders", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "id", "unavailableActions": []}'),
	('t_crm_orderItems',     '订单明细',				132, '{"tableName": "t_crm_orderItems", "timestamps": false, "autoGenId": false, "filterTargetKey": ["id"], "from": "dbsync", "underscored": false, "titleField": "id", "unavailableActions": []}')
) AS v(name, title, sort_val, opts)
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collections')
ON CONFLICT ("name") DO UPDATE SET
  "title" = EXCLUDED."title",
  "sort" = EXCLUDED."sort",
  "options" = EXCLUDED."options";

-- 4.3 Fields Registration & Display Titles (Including Foreign Key, M2M & O2M Association Fields)
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
  ('t_crm_contacts', 'assignee', 'belongsTo', 'm2o', '{"target": "users", "foreignKey": "assigneeId", "targetKey": "id", "uiSchema": {"type": "object", "title": "负责人", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}}}', 6),
  ('t_crm_contacts', 'name', 'string', 'input', '{"allowNull": true, "field": "name", "uiSchema": {"type": "string", "title": "姓名", "x-component": "Input"}}', 7),
  ('t_crm_contacts', 'phone', 'string', 'input', '{"allowNull": true, "field": "phone", "uiSchema": {"type": "string", "title": "手机号码", "x-component": "Input"}}', 8),
  ('t_crm_contacts', 'age', 'bigInt', 'integer', '{"allowNull": true, "field": "age", "uiSchema": {"type": "number", "title": "年龄", "x-component": "InputNumber"}}', 9),
  ('t_crm_contacts', 'gender', 'string', 'radioGroup', '{"allowNull": true, "field": "gender", "uiSchema": {"type": "string", "title": "性别", "x-component": "Radio.Group", "enum": [{"value": "M", "label": "男", "color": "blue"}, {"value": "F", "label": "女", "color": "red"}, {"value": "Unknown", "label": "未知", "color": "default"}]}}', 10),
  ('t_crm_contacts', 'state', 'string', 'select', '{"allowNull": true, "field": "state", "defaultValue": "sea", "uiSchema": {"type": "string", "title": "阶段状态", "x-component": "Select", "enum": [{"value": "sea", "label": "公海", "color": "blue"}, {"value": "assigned", "label": "已认领", "color": "magenta"}, {"value": "following", "label": "沟通中", "color": "green"}, {"value": "opportunity", "label": "高潜", "color": "lime"}, {"value": "customer", "label": "已购买", "color": "purple"}, {"value": "invalid", "label": "无效", "color": "default"}, {"value": "lost", "label": "流失", "color": "default"}]}}', 11),
  ('t_crm_contacts', 'tags', 'belongsToMany', 'm2m', '{"target": "t_crm_tags", "through": "t_crm_contactTags", "foreignKey": "contact", "otherKey": "tag", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "联系人标签", "x-component": "AssociationField", "x-component-props": {"multiple": true}}}', 12),
  ('t_crm_contacts', 'records', 'hasMany', 'o2m', '{"target": "t_crm_contactRecords", "foreignKey": "contactId", "sourceKey": "id", "targetKey": "id", "uiSchema": {"type": "array", "title": "沟通记录", "x-component": "AssociationField"}}', 13),

  -- t_crm_contactRecords
  ('t_crm_contactRecords', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "记录ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_contactRecords', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_contactRecords', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_contactRecords', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_contactRecords', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_contactRecords', 'contact', 'belongsTo', 'm2o', '{"target": "t_crm_contacts", "foreignKey": "contactId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联客户(联系人)", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 6),
  ('t_crm_contactRecords', 'title', 'string', 'input', '{"allowNull": true, "field": "title", "uiSchema": {"type": "string", "title": "沟通主题", "x-component": "Input"}}', 7),
  ('t_crm_contactRecords', 'type', 'string', 'select', '{"allowNull": true, "field": "type", "defaultValue": "call", "uiSchema": {"type": "string", "title": "沟通方式", "x-component": "Select", "enum": [{"value": "call", "label": "电话沟通", "color": "blue"}, {"value": "meeting", "label": "当面拜访", "color": "magenta"}, {"value": "wechat", "label": "微信沟通", "color": "green"}, {"value": "email", "label": "邮件往来", "color": "purple"}, {"value": "other", "label": "其他", "color": "default"}]}}', 8),
  ('t_crm_contactRecords', 'content', 'text', 'textarea', '{"allowNull": true, "field": "content", "uiSchema": {"type": "string", "title": "沟通内容", "x-component": "Input.TextArea"}}', 9),
  ('t_crm_contactRecords', 'recordTime', 'datetimeTz', 'datetime', '{"field": "recordTime", "uiSchema": {"type": "datetime", "title": "沟通时间", "x-component": "DatePicker", "x-component-props": {"showTime": true}}}', 10),

  -- t_crm_tags
  ('t_crm_tags', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_tags', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_tags', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_tags', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_tags', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_tags', 'tag', 'string', 'input', '{"allowNull": true, "field": "tag", "uiSchema": {"type": "string", "title": "标签名称", "x-component": "Input"}}', 6),
  ('t_crm_tags', 'state', 'string', 'select', '{"allowNull": true, "field": "state", "defaultValue": "0", "uiSchema": {"type": "string", "title": "标签状态", "x-component": "Select", "enum": [{"value": "0", "label": "正常", "color": "blue"}, {"value": "1", "label": "禁用", "color": "default"}]}}', 7),

  -- t_crm_contactTags (Through Collection with Composite Primary Key)
  ('t_crm_contactTags', 'contact', 'bigInt', 'integer', '{"primaryKey": true, "isForeignKey": true, "uiSchema": {"type": "number", "title": "contact", "x-component": "InputNumber", "x-read-pretty": true}}', 1),
  ('t_crm_contactTags', 'tag', 'bigInt', 'integer', '{"primaryKey": true, "isForeignKey": true, "uiSchema": {"type": "number", "title": "tag", "x-component": "InputNumber", "x-read-pretty": true}}', 2),

  -- t_crm_spus
  ('t_crm_spus', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_spus', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_spus', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_spus', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_spus', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_spus', 'productName', 'string', 'input', '{"allowNull": false, "field": "productName", "uiSchema": {"type": "string", "title": "产品名", "x-component": "Input"}}', 6),
  ('t_crm_spus', 'spec', 'string', 'input', '{"allowNull": true, "field": "spec", "uiSchema": {"type": "string", "title": "品规", "x-component": "Input"}}', 7),
  ('t_crm_spus', 'baseUnit', 'string', 'input', '{"allowNull": true, "field": "baseUnit", "uiSchema": {"type": "string", "title": "基本单位", "x-component": "Input"}}', 8),
  ('t_crm_spus', 'unitMeasureValue', 'float', 'number', '{"allowNull": false, "field": "unitMeasureValue", "uiSchema": {"type": "number", "title": "最小单元计量数量", "x-component": "InputNumber"}}', 9),
  ('t_crm_spus', 'unitMeasureUnit', 'string', 'input', '{"allowNull": true, "field": "unitMeasureUnit", "uiSchema": {"type": "string", "title": "最小单元计量单位", "x-component": "Input"}}', 10),
  ('t_crm_spus', 'unitSpecDisplay', 'string', 'input', '{"allowNull": true, "field": "unitSpecDisplay", "uiSchema": {"type": "string", "title": "规格显示名称", "x-component": "Input"}}', 11),

  -- t_crm_skus
  ('t_crm_skus', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_skus', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_skus', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_skus', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_skus', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_skus', 'spu', 'belongsTo', 'm2o', '{"target": "t_crm_spus", "foreignKey": "spuId", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联产品(SPU)", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "productName"}}}}', 6),
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
  ('t_crm_orders', 'contact', 'belongsTo', 'm2o', '{"target": "t_crm_contacts", "foreignKey": "fk_orders", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联客户(联系人)", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "name"}}}}', 6),
  ('t_crm_orders', 'total', 'float', 'number', '{"allowNull": true, "field": "total", "uiSchema": {"type": "number", "title": "订单总金额", "x-component": "InputNumber"}}', 7),

  -- t_crm_orderItems
  ('t_crm_orderItems', 'id', 'bigInt', 'integer', '{"allowNull": true, "primaryKey": true, "autoIncrement": true, "field": "id", "uiSchema": {"type": "number", "title": "明细ID", "x-component": "InputNumber"}}', 1),
  ('t_crm_orderItems', 'createdAt', 'datetimeTz', 'createdAt', '{"field": "createdAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Created at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 2),
  ('t_crm_orderItems', 'createdBy', 'belongsTo', 'createdBy', '{"target": "users", "foreignKey": "createdById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Created by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 3),
  ('t_crm_orderItems', 'updatedAt', 'datetimeTz', 'updatedAt', '{"field": "updatedAt", "uiSchema": {"type": "datetime", "title": "{{t(\"Last updated at\")}}", "x-component": "DatePicker", "x-component-props": {"showTime": true}, "x-read-pretty": true}}', 4),
  ('t_crm_orderItems', 'updatedBy', 'belongsTo', 'updatedBy', '{"target": "users", "foreignKey": "updatedById", "targetKey": "id", "uiSchema": {"type": "object", "title": "{{t(\"Last updated by\")}}", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "nickname"}}, "x-read-pretty": true}}', 5),
  ('t_crm_orderItems', 'sku', 'belongsTo', 'm2o', '{"target": "t_crm_skus", "foreignKey": "fk_sku", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联商品规格(SKU)", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "packageSpecDisplay"}}}}', 6),
  ('t_crm_orderItems', 'order', 'belongsTo', 'm2o', '{"target": "t_crm_orders", "foreignKey": "fk_order", "targetKey": "id", "uiSchema": {"type": "object", "title": "关联订单", "x-component": "AssociationField", "x-component-props": {"fieldNames": {"value": "id", "label": "id"}}}}', 7),
  ('t_crm_orderItems', 'quantity', 'float', 'number', '{"allowNull": false, "field": "quantity", "uiSchema": {"type": "number", "title": "数量", "x-component": "InputNumber"}}', 8),
  ('t_crm_orderItems', 'unitPrice', 'float', 'number', '{"allowNull": false, "field": "unitPrice", "uiSchema": {"type": "number", "title": "单价", "x-component": "InputNumber"}}', 9)
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

-- Batch Update primaryKey: true for all CRM tables' primary key fields (including composite keys)
UPDATE "fields"
SET "options" = (COALESCE("options"::jsonb, '{}'::jsonb) || '{"primaryKey": true}'::jsonb)::json 
WHERE ("collectionName" IN ('t_crm_contacts', 't_crm_contactRecords', 't_crm_tags', 't_crm_spus', 't_crm_skus', 't_crm_orders', 't_crm_orderItems') AND "name" = 'id')
   OR ("collectionName" = 't_crm_contactTags' AND "name" IN ('contact', 'tag'));
