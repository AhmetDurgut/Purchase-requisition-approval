# Domain: ZPR_NR_LEN_AD

Not hand-written source code - ABAP Cloud domains are maintained through an
ADT form editor (Dictionary → Domain), not a text-based DDL source, so this
file documents the settings to re-create it rather than pretending to be
compilable code.

## Purpose

Supplies the "Number Length Domain" required by the number range object
[`ZPR_NR_AD`](ZPR_NR_AD.md). ABAP Cloud's number range object editor did not
offer a suitable pre-released 10-digit numeric domain (`NUMC10` is not
available in this environment), so this is a small custom domain created to
satisfy that field.

## Settings

| Field | Value |
|---|---|
| Data Type | `NUMC` |
| Length | `10` |
| Output Length | (default) |
| Fixed Values | none |
| Value Table | none |

## How to re-create

1. Package `ZPR_APPROVAL` → New → Other ABAP Repository Object → Dictionary
   → Domain.
2. Name: `ZPR_NR_LEN_AD`, Description: `PR Number Range Length`.
3. Data Type `NUMC`, Length `10`. Leave Fixed Values and Value Table empty.
4. Activate.
