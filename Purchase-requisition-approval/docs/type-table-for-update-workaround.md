# Environment quirks and workarounds encountered building this BO

This document records the non-obvious problems hit while building this RAP
business object on this specific SAP BTP ABAP Environment (trial), in the
order they were found, so they don't get re-debugged from scratch next time.
Most of these are environment-specific quirks, not RAP/CDS design mistakes -
the syntax that failed here matches official SAP documentation and examples.

## 1. The main issue: `TYPE TABLE FOR UPDATE` / `TYPE TABLE FOR EXECUTE` fails activation

### Symptom

Any Local Handler Class (LHC) method containing a standalone declaration
like

```abap
DATA update TYPE TABLE FOR UPDATE zi_pr_header_ad\PurchaseRequisition.
```

or

```abap
DATA headers TYPE TABLE FOR EXECUTE zi_pr_header_ad\PurchaseRequisition~recalcTotal.
```

fails class activation with:

```
The type "ZI_PR_HEADER_AD\PURCHASEREQUISITION" is not an entity for which
BEHAVIOR can be defined.
```

This syntax is exactly what official SAP documentation and the
`abap-cheat-sheets` EML reference show for this purpose - the entity/alias
after `\` is correct, the behavior definition activates cleanly on its own,
the CDS view activates cleanly on its own, and the persistence table
activates cleanly on its own.

### What was ruled out

- Renaming the class, regenerating it from scratch via the BDEF's
  "Create behavior implementation class" quick fix.
- A completely new, unrelated, minimal test object (`ZTEST_ROOT` /
  `ZI_TEST_ROOT`, one field, no draft, one LHC method) - **same error**.
- Logging off/on, closing and reopening Eclipse, mass-activating the whole
  package.
- Checking the class's ABAP Language Version (correctly "ABAP for Cloud
  Development").
- Moving the type declaration from a method-local `DATA` statement to a
  `TYPES` statement in the class's `PRIVATE SECTION` - **same error**.
- **Deleting the entire trial instance and provisioning a brand new one from
  scratch** - the identical minimal test object reproduced the identical
  error on the fresh instance.

That last point is the important one: this is not corrupted state in one
instance. It reproduces on a freshly provisioned SAP BTP ABAP Environment
trial (shared plan), which points at a defect/limitation of that specific
plan tier's RAP/EML type generation, not at anything in this project's code.

### Workaround used throughout this project

Never declare `TYPE TABLE FOR UPDATE` / `TYPE TABLE FOR CREATE` /
`TYPE TABLE FOR DELETE` / `TYPE TABLE FOR EXECUTE` as a standalone type.
Build the table **inline**, directly as the `WITH` / `FROM` argument of the
`MODIFY ENTITIES` statement - exactly like the framework-generated
"simple" methods (`setInitialStatus`, `approve`, `reject`, `requestInfo`)
already do. For methods that previously accumulated rows in a loop before
one batched `MODIFY ENTITIES`, the loop body now calls `MODIFY ENTITIES`
once per row instead, with the row built inline:

```abap
" Before (fails to activate on this environment):
DATA update TYPE TABLE FOR UPDATE zi_pr_header_ad\PurchaseRequisition.
LOOP AT prs INTO DATA(pr) WHERE ...
  update = VALUE #( BASE update ( %tky = pr-%tky PrNumber = lv_number ) ).
ENDLOOP.
MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
  ENTITY PurchaseRequisition UPDATE FIELDS ( PrNumber ) WITH update.

" After (activates fine - type inferred inline from the MODIFY ENTITIES context):
LOOP AT prs INTO DATA(pr) WHERE ...
  MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
    ENTITY PurchaseRequisition
      UPDATE FIELDS ( PrNumber )
      WITH VALUE #( ( %tky = pr-%tky PrNumber = lv_number ) ).
ENDLOOP.
```

The same pattern replaced `TYPE TABLE FOR EXECUTE` in
`calculateItemAmount` - deduplication of parent headers before calling
`EXECUTE recalcTotal` is done with a plain `STANDARD TABLE OF sysuuid_x16`
instead of a RAP-typed table, and `EXECUTE ... FROM` gets its argument
inline per row.

See [`ZBP_I_PR_HEADER_AD.clas.abap`](../src/behavior/ZBP_I_PR_HEADER_AD.clas.abap)
for the full, working implementation.

## 2. `CURR`/`QUAN` fields need a reference field, and that reference check hits a non-released table

### Symptom

A field of type `abap.curr(15,2)` in a `define table` persistence source
requires `@Semantics.amount.currencyCode` pointing at a currency-key field
(same for `abap.quan` and `@Semantics.quantity.unitOfMeasure`/unit). Without
it: `Annotation with reference to currency code for field X is missing`.
With it, if the currency/unit field is `waers`/`meins` (data elements whose
domain's value table is `TCURC`/`T006`) **or** the built-in `abap.cuky`/
`abap.unit` types plus the annotation: `The use of Table CURRENCY
[T006] is not permitted` - `TCURC`/`T006` are not released for this
environment's restricted tables.

### Workaround

Use `abap.decfloat34` instead of `abap.curr`/`abap.quan` for amount/quantity
fields. Per the ABAP Dictionary docs, the reference-field annotation is
**mandatory** for `CURR`/`QUAN` but **optional** for `DECFLOAT16`/
`DECFLOAT34` - so it can simply be omitted, and the currency-check-table
lookup that fails never gets triggered. `currency`/`unit` themselves stay as
plain `abap.cuky`/`abap.unit(3)` (no domain, so no value table to reject).
See `total_amount`/`currency` in
[`ZPR_HEADER_AD.ddls`](../src/database/ZPR_HEADER_AD.ddls) and
`quantity`/`unit`/`price`/`amount`/`currency` in
[`ZPR_ITEM_AD.ddls`](../src/database/ZPR_ITEM_AD.ddls).

## 3. Number range object names are limited to 10 characters

`ZPR_RANGE_AD` (12 characters) was rejected. Renamed to `ZPR_NR_AD` (9
characters) - see [`ZPR_NR_AD.md`](../src/dictionary/ZPR_NR_AD.md).

## 4. Root/child CDS views with mutual associations need a two-pass activation

`ZI_PR_HEADER_AD`'s `composition ... of ZI_PR_ITEM_AD as _Item` and
`ZI_PR_ITEM_AD`'s `association to parent ZI_PR_HEADER_AD as _Header` refer
to each other. On first activation neither exists yet, so each fails to
resolve the other. Fix: temporarily strip the `association to parent`
block out of `ZI_PR_ITEM_AD`, activate it standalone, activate
`ZI_PR_HEADER_AD` (which can now see the item view), then restore the
association in `ZI_PR_ITEM_AD` and activate it again. Same two-pass
approach needed for the projection views (`ZC_PR_HEADER_AD` /
`ZC_PR_ITEM_AD`).

## 5. Draft-enabled behavior definitions fail with misleading cascading errors when a dependency is missing

While `ZA_PR_REJECT_AD` (the reject action's parameter abstract entity)
didn't exist yet, activating `ZI_PR_HEADER_AD.bdef` produced errors like
`"ZI_PR_HEADER_AD" is not a lock entity ("lock master") and hence cannot
define a "ACTIVATE" action` and `every entity must be flagged as
"authorization master"...` - even though `lock master` and
`authorization master ( instance )` were both present and correctly
spelled. These are misattributed symptoms of the missing type, not real
lock/authorization problems. Once the missing dependency (here,
`ZA_PR_REJECT_AD`; the same pattern showed up for missing draft tables
too) was created, all of these cleared up. General lesson for this
environment: if a behavior definition throws several unrelated-looking
structural errors at once, check for a missing referenced type/table
before trying to fix each error individually.

## 6. Projection-level draft actions use `use action X;`, not `use draft action X;`

`use draft;` at the top of a projection behavior definition is enough to
put draft actions in context. Writing `use draft action Edit;` (mirroring
the base behavior definition's `draft action Edit;`) fails with
`"action | association | create | delete | event | function | key | update"
was expected, not "draft"`. Fix: drop the `draft` keyword at the
projection level - `use action Edit;`, `use action Activate;`, etc. See
[`ZC_PR_HEADER_AD.bdef`](../src/projection/ZC_PR_HEADER_AD.bdef).

## 7. Metadata extension quirks on this environment

- `@UI.headerInfo` is rejected with `used at wrong position (wrong scope)`
  on **both** `ZC_PR_HEADER_AD` (root) and `ZC_PR_ITEM_AD` (non-root) in
  this environment, despite being standard, documented Fiori Elements
  syntax. It was removed from both metadata extensions; this only costs
  the customized Object Page title/subtitle styling, not any
  functionality (facets, actions, fields, criticality-colored status all
  work without it).
- Every element referenced in an `annotate view ... with { }` block must
  carry at least one annotation on this environment -
  `Element 'X' must have at least one annotation`. Fields that are only
  semantic units (`Unit` for `Quantity`, `Currency` for `TotalAmount`/
  `Price`/`Amount`) and shouldn't get their own UI presence need an
  explicit `@UI.hidden: true` rather than being listed bare.

## 8. Known open item: Items table shows "Unable to find annotationPath undefined"

At the point this project was rebuilt end-to-end, the Object Page's "Items"
facet (`type: #LINEITEM_REFERENCE`, `targetElement: '_Item'` in
[`ZC_PR_HEADER_MDE_AD.ddlx`](../src/metadata/ZC_PR_HEADER_MDE_AD.ddlx))
rendered the section but showed `Unable to find annotationPath undefined`
instead of the item table, even after a hard browser refresh / private
window. Not yet root-caused - everything else (draft create, header fields,
status-driven action enablement) works end-to-end. Next things to try: a
minimal `#LINEITEM_REFERENCE` reproduction the same way the main bug above
was isolated, and double-checking whether this environment needs a
`targetQualifier` alongside `targetElement` for this facet type.
