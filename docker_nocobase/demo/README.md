# NocoBase 物理表建表与元数据 (Metadata) 配置指南

本目录包含用于重构及初始化 CRM 业务系统的 PostgreSQL DDL 脚本 [nocobase-crm.sql](docker_nocobase/demo/nocobase-crm.sql)。

为了避免后续在直接修改数据库元数据或创建物理表时导致 NocoBase 报错（例如：*“当数据表没有主键时...”* 或页面区块选择器无法选取数据表），请严格遵循以下设计原则与最佳实践。

---

## 目录
1. [架构概述](#1-架构概述)
2. [物理表建表规范 (Physical Schema)](#2-物理表建表规范-physical-schema)
3. [NocoBase 元数据注册规范 (Metadata)](#3-nocobase-元数据注册规范-metadata)
   - [3.1 数据表注册 (`collections`)](#31-数据表注册-collections)
   - [3.2 字段注册 (`fields`)](#32-字段注册-fields)
   - [3.3 关联字段注册 (`m2o`, `o2m`, `m2m`)](#33-关联字段注册-m2o-o2m-m2m)
4. [常见陷阱与排查 checklist](#4-常见陷阱与排查-checklist)

---

## 1. 架构概述

NocoBase 采用 **“物理表 + 元数据引擎”** 的双层架构：
* **物理数据库**：存储具体的 PostgreSQL `CREATE TABLE`、`SEQUENCE`、索引及外键约束。
* **NocoBase 元数据 (Metadata)**：存储在 `collections`、`fields`、`collectionCategories` 等系统表中，驱动前端 UI Schema 渲染、区块（Block）创建、关联拉取及权限控制。

> ⚠️ **核心原则**：直接修改数据库中的 `collections` / `fields` 表后，NocoBase 后端内存中的 Schema Cache 并不会自动刷新。**修改 SQL 后必须重启 NocoBase 容器** (`docker restart svc-nocobase`)，否则前端读取到的仍是旧模型。

---

## 2. 物理表建表规范 (Physical Schema)

1. **表名与序列前缀**：
   * 业务表统一增加 `t_crm_` 前缀（如 `t_crm_contacts`, `t_crm_orders`）。
   * 序列命名规范：`t_crm_<table_name>_id_seq`。
   * 注意：在 SQL 的 `nextval` 默认值中，若序列或表名包含大小写混排，必须使用转义双引号，例如：
     ```sql
     DEFAULT nextval('"t_crm_orderItems_id_seq"'::regclass)
     ```

2. **内置审计字段顺序**：
   * 每个业务表均应包含 4 个通用内置审计列：`createdAt`、`createdById`、`updatedAt`、`updatedById`。
   * 物理列排列顺序：紧跟在主键 `id` 之后。
     ```sql
     "id" bigint NOT NULL DEFAULT nextval('t_crm_contacts_id_seq'::regclass),
     "createdAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
     "createdById" bigint,
     "updatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
     "updatedById" bigint,
     ```

3. **物理外键与多对多连接表**：
   * 多对多（M2M）关系通过单独的物理连接表实现（如 `t_crm_contactTags`），采用复合主键 `PRIMARY KEY ("contact", "tag")` 并配置外键级联删除 (`ON DELETE CASCADE`)。

---

## 3. NocoBase 元数据注册规范 (Metadata)

### 3.1 数据表注册 (`collections`)

在 `collections` 系统表中注册表元数据时，`options` JSON 必须满足：

```json
{
  "template": "general",
  "tableName": "t_crm_contacts",
  "timestamps": false,
  "autoGenId": false,
  "from": "dbsync",
  "underscored": false,
  "titleField": "name",
  "unavailableActions": []
}
```

#### 关键字段要求：
1. **`"template": "general"`（必须）**：
   * 🚨 **重要陷阱**：页面点击“+ 添加区块”时，NocoBase 的 `SchemaInitializer` 会强校验 `template`。**若缺少 `"template": "general"`，该数据表在添加区块菜单中将被置灰禁用**，并显示需要唯一标识符的警告。
2. **`filterTargetKey` 处理原则**：
   * 对于**标准单主键表**：**不要**在 `options` JSON 中手动将其设置为数组 `["id"]`！只需确保 `fields` 表中 `id` 字段打上了 `"primaryKey": true` 标记，NocoBase 会自动推导为字符串 `"id"`。
   * 对于**多对多连接表**：可配置为数组 `["contact", "tag"]`。
3. **关系表隐藏 (`hidden: true`)**：
   * 对于像 `t_crm_contactTags` 这类纯关系中间表（Through Collection），应设置 `"hidden": true` 以及 `"isThrough": true`。这样该中间表不会作为独立业务表显示在数据源列表和建块菜单中，同时又不影响联系人与其标签的多对多关联操作。

---

### 3.2 字段注册 (`fields`)

`fields` 表记录各表列在 UI 界面中的渲染组件与数据类型。

1. **主键字段 (`id`) 配置**：
   ```json
   {
     "primaryKey": true,
     "autoIncrement": true,
     "allowNull": false,
     "uiSchema": {
       "type": "number",
       "title": "ID",
       "x-component": "InputNumber"
     }
   }
   ```
2. **内置审计字段配置 (System Field Interfaces)**：
   * `createdAt` -> `interface: "createdAt"`
   * `createdBy` -> `interface: "createdBy"`, `type: "belongsTo"`, `target: "users"`, `foreignKey: "createdById"`
   * `updatedAt` -> `interface: "updatedAt"`
   * `updatedBy` -> `interface: "updatedBy"`, `type: "belongsTo"`, `target: "users"`, `foreignKey: "updatedById"`

---

### 3.3 关联字段注册 (`m2o`, `o2m`, `m2m`)

1. **一对多 / 多对一 (Many-to-One / `m2o` & `belongsTo`)**：
   从表包含外键 `contactId` 指向主表 `t_crm_contacts.id`：
   ```json
   {
     "target": "t_crm_contacts",
     "foreignKey": "contactId",
     "targetKey": "id",
     "uiSchema": {
       "type": "object",
       "title": "关联客户",
       "x-component": "AssociationField",
       "x-component-props": { "fieldNames": { "value": "id", "label": "name" } }
     }
   }
   ```

2. **一对多反向 (One-to-Many / `o2m` & `hasMany`)**：
   主表 `t_crm_contacts` 关联从表 `t_crm_contactRecords`：
   ```json
   {
     "target": "t_crm_contactRecords",
     "foreignKey": "contactId",
     "sourceKey": "id",
     "targetKey": "id",
     "uiSchema": {
       "type": "array",
       "title": "沟通记录",
       "x-component": "AssociationField"
     }
   }
   ```

3. **多对多 (Many-to-Many / `m2m` & `belongsToMany`)**：
   `t_crm_contacts` 关联 `t_crm_tags`（通过中间表 `t_crm_contactTags`）：
   ```json
   {
     "target": "t_crm_tags",
     "through": "t_crm_contactTags",
     "foreignKey": "contact",
     "otherKey": "tag",
     "sourceKey": "id",
     "targetKey": "id",
     "uiSchema": {
       "type": "array",
       "title": "联系人标签",
       "x-component": "AssociationField",
       "x-component-props": { "multiple": true }
     }
   }
   ```

---

## 4. 常见陷阱与排查 Checklist

* [ ] **陷阱 1：SQL 执行后网页端没有变化或提示主键错误**
  * **原因**：NocoBase Node.js 内存缓存未刷新。
  * **解法**：执行 `docker restart svc-nocobase`。

* [ ] **陷阱 2：页面“+ 添加区块”时数据表置灰无法选择**
  * **原因**：`collections` 表中对应记录的 `options` 缺失 `"template": "general"`，或 `filterTargetKey` 格式错配。
  * **解法**：检查 `collections.options` 确保包含 `"template": "general"`。

* [ ] **陷阱 3：看懂抽屉菜单中的“记录唯一标识符”说明**
  * **说明**：在编辑数据表（Edit Collection）抽屉表单中，`记录唯一标识符` 字段下方的提示文字为标准静态说明文本，并非报错信息。

* [ ] **陷阱 4：中间关系表污染数据源选择列表**
  * **解法**：中间关系表（如 `t_crm_contactTags`）设置 `hidden = true` 即可隐入后台。
