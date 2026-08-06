CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE "user" (
  "id" text PRIMARY KEY NOT NULL,
  "name" text NOT NULL,
  "email" text NOT NULL,
  "email_verified" boolean DEFAULT false NOT NULL,
  "image" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "user_email_unique" UNIQUE ("email")
);

CREATE TABLE "session" (
  "id" text PRIMARY KEY NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "token" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "ip_address" text,
  "user_agent" text,
  "user_id" text NOT NULL,
  CONSTRAINT "session_token_unique" UNIQUE ("token"),
  CONSTRAINT "session_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE cascade
);

CREATE TABLE "account" (
  "id" text PRIMARY KEY NOT NULL,
  "account_id" text NOT NULL,
  "provider_id" text NOT NULL,
  "user_id" text NOT NULL,
  "access_token" text,
  "refresh_token" text,
  "id_token" text,
  "access_token_expires_at" timestamp with time zone,
  "refresh_token_expires_at" timestamp with time zone,
  "scope" text,
  "password" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "account_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE cascade
);

CREATE TABLE "verification" (
  "id" text PRIMARY KEY NOT NULL,
  "identifier" text NOT NULL,
  "value" text NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone
);

CREATE TYPE "entry_kind" AS ENUM ('expense', 'card_expense', 'income');
CREATE TYPE "income_source" AS ENUM ('salary', 'other');
CREATE TYPE "entry_category" AS ENUM ('food', 'daily', 'transport', 'entertainment', 'housing', 'business', 'health', 'other');
CREATE TYPE "employment_type" AS ENUM ('employee', 'freelance', 'part_time', 'contract');
CREATE TYPE "rule_direction" AS ENUM ('expense', 'income');

CREATE TABLE "user_settings" (
  "user_id" text PRIMARY KEY NOT NULL,
  "employment_type" "employment_type" NOT NULL,
  "savings_goal" integer,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "user_settings_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE cascade
);

CREATE TABLE "card" (
  "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "name" text NOT NULL,
  "closing_day" integer NOT NULL,
  "payment_day" integer NOT NULL,
  "revolving_amount" integer,
  "credit_limit" integer,
  "carryover_balance" integer DEFAULT 0 NOT NULL,
  "created_date" date NOT NULL,
  "archived" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "card_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE cascade
);

CREATE TABLE "recurring_rule" (
  "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "direction" "rule_direction" NOT NULL,
  "name" text NOT NULL,
  "amount" integer NOT NULL,
  "day_of_month" integer NOT NULL,
  "card_id" uuid,
  "category" "entry_category",
  "start_month" text NOT NULL,
  "active" boolean DEFAULT true NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "recurring_rule_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE cascade,
  CONSTRAINT "recurring_rule_card_id_card_id_fk" FOREIGN KEY ("card_id") REFERENCES "card"("id") ON DELETE restrict
);

CREATE TABLE "entry" (
  "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "kind" "entry_kind" NOT NULL,
  "amount" integer NOT NULL,
  "date" date NOT NULL,
  "year_month" text NOT NULL,
  "category" "entry_category",
  "card_id" uuid,
  "income_source" "income_source",
  "note" text,
  "source_rule_id" uuid,
  "is_manually_edited" boolean DEFAULT false NOT NULL,
  "deleted_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "entry_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE cascade,
  CONSTRAINT "entry_card_id_card_id_fk" FOREIGN KEY ("card_id") REFERENCES "card"("id") ON DELETE restrict,
  CONSTRAINT "entry_source_rule_id_recurring_rule_id_fk" FOREIGN KEY ("source_rule_id") REFERENCES "recurring_rule"("id") ON DELETE set null
);

CREATE INDEX "session_user_id_idx" ON "session" ("user_id");
CREATE INDEX "account_user_id_idx" ON "account" ("user_id");
CREATE INDEX "card_user_idx" ON "card" ("user_id");
CREATE INDEX "recurring_rule_user_idx" ON "recurring_rule" ("user_id");
CREATE UNIQUE INDEX "entry_rule_month_uq" ON "entry" ("source_rule_id", "year_month") WHERE "source_rule_id" is not null;
CREATE INDEX "entry_user_month_idx" ON "entry" ("user_id", "year_month");
CREATE INDEX "entry_user_card_date_idx" ON "entry" ("user_id", "card_id", "date");
