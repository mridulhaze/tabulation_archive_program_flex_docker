/*
 Navicat Premium Dump SQL

 Source Server         : nu_results_archive
 Source Server Type    : Oracle
 Source Server Version : 120100 (Oracle Database 12c Enterprise Edition Release 12.1.0.2.0 - 64bit Production
With the Partitioning, OLAP, Advanced Analytics and Real Application Testing options)
 Source Host           : 103.113.200.20:1521
 Source Schema         : NU

 Target Server Type    : Oracle
 Target Server Version : 120100 (Oracle Database 12c Enterprise Edition Release 12.1.0.2.0 - 64bit Production
With the Partitioning, OLAP, Advanced Analytics and Real Application Testing options)
 File Encoding         : 65001

 Date: 19/02/2026 17:30:24
*/


-- ----------------------------
-- Table structure for T_USER
-- ----------------------------
DROP TABLE "NU"."T_USER";
CREATE TABLE "NU"."T_USER" (
  "ID" NUMBER VISIBLE DEFAULT "NU"."ISEQ$$_169668".nextval NOT NULL,
  "USERNAME" VARCHAR2(50 BYTE) VISIBLE NOT NULL,
  "PASSWORD" VARCHAR2(1000 BYTE) VISIBLE NOT NULL,
  "ROLE" VARCHAR2(30 BYTE) VISIBLE NOT NULL,
  "CREATED_AT" TIMESTAMP(6) VISIBLE DEFAULT CURRENT_TIMESTAMP
)
LOGGING
NOCOMPRESS
PCTFREE 10
INITRANS 1
STORAGE (
  INITIAL 65536 
  NEXT 1048576 
  MINEXTENTS 1
  MAXEXTENTS 2147483645
  BUFFER_POOL DEFAULT
)
PARALLEL 1
NOCACHE
DISABLE ROW MOVEMENT
;

-- ----------------------------
-- Primary Key structure for table T_USER
-- ----------------------------
ALTER TABLE "NU"."T_USER" ADD CONSTRAINT "SYS_C0015484" PRIMARY KEY ("ID");

-- ----------------------------
-- Uniques structure for table T_USER
-- ----------------------------
ALTER TABLE "NU"."T_USER" ADD CONSTRAINT "SYS_C0015485" UNIQUE ("USERNAME") NOT DEFERRABLE INITIALLY IMMEDIATE NORELY VALIDATE;

-- ----------------------------
-- Checks structure for table T_USER
-- ----------------------------
ALTER TABLE "NU"."T_USER" ADD CONSTRAINT "SYS_C0015480" CHECK ("ID" IS NOT NULL) NOT DEFERRABLE INITIALLY IMMEDIATE NORELY VALIDATE;
ALTER TABLE "NU"."T_USER" ADD CONSTRAINT "SYS_C0015481" CHECK ("USERNAME" IS NOT NULL) NOT DEFERRABLE INITIALLY IMMEDIATE NORELY VALIDATE;
ALTER TABLE "NU"."T_USER" ADD CONSTRAINT "SYS_C0015482" CHECK ("PASSWORD" IS NOT NULL) NOT DEFERRABLE INITIALLY IMMEDIATE NORELY VALIDATE;
ALTER TABLE "NU"."T_USER" ADD CONSTRAINT "SYS_C0015483" CHECK ("ROLE" IS NOT NULL) NOT DEFERRABLE INITIALLY IMMEDIATE NORELY VALIDATE;
