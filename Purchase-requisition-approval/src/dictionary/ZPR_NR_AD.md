# Number Range Object: ZPR_NR_AD

Not hand-written source code - ABAP Cloud number range objects are maintained
through an ADT form editor (Dictionary → Number Range Object), not a
text-based DDL source, so this file documents the settings to re-create it
rather than pretending to be compilable code.

## Purpose

Supplies `PrNumber` (the human-readable business key) on submit, via
`cl_numberrange_runtime=>number_get( nr_range_nr = '01' object = 'ZPR_NR_AD' )`
in `LHC_PURCHASEREQUISITION=>setPRNumber` (see
[`ZBP_I_PR_HEADER_AD.clas.abap`](../behavior/ZBP_I_PR_HEADER_AD.clas.abap)).

## Naming note

The original design called this object `ZPR_RANGE_AD`, but number range
object names are limited to **10 characters** - `ZPR_RANGE_AD` is 12 and was
rejected at creation ("literal is not type-compatible with the formal
parameter OBJECT" when used in the `NUMBER_GET` call). Renamed to
`ZPR_NR_AD` (9 characters).

## Settings

| Field | Value |
|---|---|
| Number Length Domain | [`ZPR_NR_LEN_AD`](ZPR_NR_LEN_AD.md) (custom NUMC10 domain) |
| Percent Warning | `10` |
| Rolling | checked |
| Until Year / Prefix | unchecked |
| Buffering | No Buffering |
| Buffered Numbers | `0` |

## Interval

| Number | From | To |
|---|---|---|
| `01` | `0000000001` | `9999999999` |

## How to re-create

1. Create [`ZPR_NR_LEN_AD`](ZPR_NR_LEN_AD.md) first (the number length
   domain).
2. Package `ZPR_APPROVAL` → New → Other ABAP Repository Object → Dictionary
   → Number Range Object.
3. Name: `ZPR_NR_AD`, Description: `PR Number Range`.
4. Number Length Domain: browse for `ZPR_NR_LEN_AD`. Rolling checked, No
   Buffering.
5. Activate, then maintain the interval above (Maintain Intervals → no `01`,
   from `0000000001` to `9999999999`).
