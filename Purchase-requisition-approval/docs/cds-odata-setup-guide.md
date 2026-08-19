# CDS / OData Setup Guide — Purchase Requisition Approval

A complete, click-by-click walkthrough for activating every object in this
project on a real SAP BTP ABAP Environment / S/4HANA system via ADT
(Eclipse), starting from nothing and ending with a working Fiori Elements
preview. Every object name, dependency, and behavior described below comes
directly from the source files in `src/` — nothing here is a generic RAP
checklist.

## 1. Overview

| Layer | Objects | Count |
|---|---|---|
| Database | `ZPR_HEADER`, `ZPR_ITEM` | 2 tables |
| Data Model (interface) | `ZI_PR_HEADER`, `ZI_PR_ITEM`, `ZA_PR_REJECT` | 3 views (2 root/child + 1 abstract entity) |
| Behavior | `ZI_PR_HEADER.bdef` (defines behavior for both `ZI_PR_HEADER` and `ZI_PR_ITEM`), `ZBP_I_PR_HEADER` | 1 behavior definition + 1 implementation class |
| Projection | `ZC_PR_HEADER`, `ZC_PR_ITEM` (views), `ZC_PR_HEADER.bdef`, `ZC_PR_ITEM.bdef` (behavior) | 2 views + 2 behavior definitions |
| Metadata Extension | `ZC_PR_HEADER_MDE`, `ZC_PR_ITEM_MDE` | 2 |
| Service | `ZUI_PR_HEADER` (service definition) + 1 service binding created directly in the system (no source file) | 1 file + 1 binding |

That's 14 source files across 6 layers, plus two draft tables
(`zpr_header_d`, `zpr_item_d`) that ADT generates for you rather than
anything you write by hand — more on that in step 4.

**Why order matters:** every CDS object in this chain is defined in terms
of the one below it — a projection view says `as projection on
ZI_PR_HEADER`, a behavior definition says `for ZI_PR_HEADER`, a metadata
extension says `annotate view ZC_PR_HEADER`. ADT resolves each of those
references against the DDIC at activation time, so if the referenced
object doesn't exist yet (or exists but isn't active), activation fails
with a "not found" or "not active" error. Working through the layers in
dependency order — database → data model → behavior → projection →
metadata → service — avoids that entirely. There are two spots in this
project (interface layer, projection layer) where two views reference
*each other*, which needs a slightly different approach — see steps 3 and
5.

**Prerequisites:**
- Eclipse with the ABAP Development Tools (ADT) plugin installed.
- A working connection to an SAP BTP ABAP Environment trial/free-tier
  system or an S/4HANA system with ABAP Cloud development enabled.
- A developer user with authorization to create DDIC and RAP objects.
- An ABAP package to hold all of this — either a local/test package
  (`$TMP`-style, non-transportable) for a personal trial system, or a
  proper transportable package with a transport request if you're working
  against a shared system.

No Access Control (DCL) objects exist in this project — there's no
`.dcls` file in `src/`, and both interface views carry
`@AccessControl.authorizationCheck: #NOT_REQUIRED`, so there's nothing to
activate on that front.

## 2. Database tables

`ZPR_HEADER` and `ZPR_ITEM` are plain `define table` DDIC sources. `ZPR_ITEM`
carries a `parent_uuid` field that's documented in a comment as the
composition link to `ZPR_HEADER.pr_uuid`, but it isn't declared as an
actual foreign key in the table DDL — so there is no hard activation-order
dependency between the two tables; either would activate fine on its own.
Activate `ZPR_HEADER` first anyway, purely for readability, since it's the
parent conceptually:

1. In your package, create a Database Table (`New > Other ABAP Repository
   Object > Dictionary > Database Table`) named `ZPR_HEADER`, paste in the
   contents of `src/database/ZPR_HEADER.ddls`, save, and activate
   (`Ctrl+F3` or the Activate toolbar button).
2. Repeat for `ZPR_ITEM` using `src/database/ZPR_ITEM.ddls`.

## 3. Data model (interface) views

`ZA_PR_REJECT` is an abstract entity (no `SELECT`, no persistence — just a
single `reject_reason` field) and has no dependency on anything else in
this layer. Create and activate it whenever convenient, before you get to
the behavior definition in step 4, which references it as `action reject
parameter ZA_PR_REJECT`.

`ZI_PR_HEADER` and `ZI_PR_ITEM` reference **each other** and cannot be
activated one at a time:

- `ZI_PR_HEADER` declares `composition [0..*] of ZI_PR_ITEM as _Item`.
- `ZI_PR_ITEM` declares `association to parent ZI_PR_HEADER as _Header`.

If you create and try to activate `ZI_PR_HEADER` first, ADT will complain
that `ZI_PR_ITEM` doesn't exist yet; if you try `ZI_PR_ITEM` first, it'll
complain that `ZI_PR_HEADER` doesn't exist. Neither order works in
isolation. The way through this is:

1. Create both view entities (`New > Other ABAP Repository Object > Core
   Data Services > Data Definition`), paste in the contents of
   `src/data-model/ZI_PR_HEADER.ddls` and `src/data-model/ZI_PR_ITEM.ddls`
   respectively, and **save both without activating either one yet**.
2. Select both files together in the Project Explorer (`Ctrl`-click to
   multi-select), right-click, and choose **Activate**. ADT batches the
   two activations into a single pass and resolves the mutual reference
   there — this is the standard way to bring up a circular RAP composition
   pair.

## 4. Behavior definition + implementation class

`ZI_PR_HEADER.bdef` opens with `managed implementation in class
zbp_i_pr_header unique;` and defines behavior for both `ZI_PR_HEADER`
(alias `PurchaseRequisition`) and `ZI_PR_ITEM` (alias
`PurchaseRequisitionItem`) in the same file — one behavior definition
source covers the whole root/child pair.

1. With `ZI_PR_HEADER` and `ZI_PR_ITEM` active, create a new Behavior
   Definition (`New > Other ABAP Repository Object > Core Data Services >
   Behavior Definition`) on `ZI_PR_HEADER`, paste in the contents of
   `src/behavior/ZI_PR_HEADER.bdef`, and save.
2. ADT will flag `zbp_i_pr_header` as an implementing class that doesn't
   exist yet. Place the cursor on the `implementation in class
   zbp_i_pr_header` line and use the Quick Fix (`Ctrl+1`) to generate the
   class stub — this creates `ZBP_I_PR_HEADER` already wired up `FOR
   BEHAVIOR OF zi_pr_header`.
3. Open the generated class and replace its contents with
   `src/behavior/ZBP_I_PR_HEADER.clas.abap` (the determinations,
   validations, actions, `get_instance_features`, and
   `get_instance_authorizations` implementations). Activate the class.
4. Activate the behavior definition.

**Draft tables — a required extra step.** `ZI_PR_HEADER.bdef` includes
`with draft;`, and the behavior definition names `draft table
zpr_header_d` and `draft table zpr_item_d`. These two tables do not exist
as source files anywhere in this project, and you will not find them
under `src/database/` — they are meant to be generated by ADT, not
hand-written. When you activate the behavior definition (or as soon as
you type `with draft;` and save), ADT will report both draft tables as
missing. Place the cursor directly on the `with draft;` line and trigger
the Quick Fix (`Ctrl+1`); it offers to generate and activate
`zpr_header_d` and `zpr_item_d` for you, shaped automatically from
`ZPR_HEADER`/`ZPR_ITEM` plus RAP's own draft administration fields. Do
this before trying to activate the behavior definition itself, or the
activation will fail on the missing draft tables.

## 5. Projection layer

The two projection views reference each other the same way the interface
views did, just with redirected associations instead of the original
composition/to-parent pair:

- `ZC_PR_HEADER` is `as projection on ZI_PR_HEADER as PurchaseRequisition`
  and redirects the composition: `_Item : redirected to composition child
  ZC_PR_ITEM`.
- `ZC_PR_ITEM` is `as projection on ZI_PR_ITEM as
  PurchaseRequisitionItem` and redirects the to-parent association:
  `_Header : redirected to parent ZC_PR_HEADER`.

Same circular reference, same fix:

1. Create `ZC_PR_HEADER` and `ZC_PR_ITEM` as projection views on
   `ZI_PR_HEADER` / `ZI_PR_ITEM`, paste in
   `src/projection/ZC_PR_HEADER.ddls` and `src/projection/ZC_PR_ITEM.ddls`,
   save both without activating.
2. Multi-select both and Activate together, exactly as in step 3.

Both carry `@Metadata.allowExtensions: true` — that's what step 6 needs.

With the projection views active, activate the two projection behavior
definitions. Unlike the views, `ZC_PR_HEADER.bdef` and `ZC_PR_ITEM.bdef`
don't reference each other's ABAP syntax directly (the association
between them is already resolved at the CDS view level), so there's no
circular-activation problem here — either order works, as long as the
matching projection view and the root behavior definition
(`ZI_PR_HEADER.bdef`) are already active:

1. Create a Behavior Definition on `ZC_PR_ITEM` (`projection;`), paste in
   `src/projection/ZC_PR_ITEM.bdef`, activate.
2. Create a Behavior Definition on `ZC_PR_HEADER` (`projection; strict (
   2 ); use draft;`), paste in `src/projection/ZC_PR_HEADER.bdef`,
   activate.

## 6. Metadata extensions

`ZC_PR_HEADER_MDE` (`annotate view ZC_PR_HEADER with { ... }`) and
`ZC_PR_ITEM_MDE` (`annotate view ZC_PR_ITEM with { ... }`) each extend one
projection view. Both target views already carry
`@Metadata.allowExtensions: true`, which is a hard requirement — a
metadata extension cannot activate against a view that doesn't declare it.
The two extension files don't reference each other, so order between them
doesn't matter:

1. Create a Metadata Extension (`New > Other ABAP Repository Object > Core
   Data Services > Metadata Extension`) on `ZC_PR_HEADER`, paste in
   `src/metadata/ZC_PR_HEADER_MDE.ddlx`, activate.
2. Create a Metadata Extension on `ZC_PR_ITEM`, paste in
   `src/metadata/ZC_PR_ITEM_MDE.ddlx`, activate.

## 7. Service definition

`ZUI_PR_HEADER.srvd` exposes exactly one view:

```
define service ZUI_PR_HEADER {
  expose ZC_PR_HEADER as PurchaseRequisition;
}
```

`ZC_PR_ITEM` is not listed here and gets no entity set of its own — it's
reached only through `ZC_PR_HEADER`'s `_Item` composition, which is
already redirected to it. The entity set you'll see later in the service
binding and the Fiori preview is named `PurchaseRequisition`, not
`ZC_PR_HEADER`.

1. Create a Service Definition (`New > Other ABAP Repository Object > Core
   Data Services > Service Definition`) on `ZC_PR_HEADER`, paste in
   `src/service/ZUI_PR_HEADER.srvd`, activate.

## 8. Service binding

There is no source file for the service binding — as documented in
[src/service/README.md](../src/service/README.md), it's an ADT object you
create visually, not something you write or paste in. Nothing under
`src/` covers this step; do it directly in ADT:

1. Right-click `ZUI_PR_HEADER` → `New > Service Binding`.
2. Give it a name and description (e.g. `ZUI_PR_HEADER_O4`), and set
   **Binding Type** to **OData V4 - UI**. The service definition field
   should already point at `ZUI_PR_HEADER`.
3. Finish the wizard — this opens the Service Binding editor. Click
   **Activate**.
4. Click **Publish**. This is the step people skip most often, and it's
   the single most common reason a freshly built service "doesn't work"
   even though every object underneath it activated cleanly: activating a
   service binding only makes it exist locally, while publishing is what
   registers it with the runtime's service catalog so it's actually
   callable. If `PurchaseRequisition` doesn't show up when you try to
   preview it, come back here first.

## 9. Previewing the Fiori Elements app

From the Service Binding editor, select the `PurchaseRequisition` entity
set and click **Preview**. Based on the annotations in
`ZC_PR_HEADER_MDE.ddlx` and `ZC_PR_ITEM_MDE.ddlx`, here's what you should
see:

- **List Report** — filter bar with **Requester**, **Status**, and **Cost
  Center** (in that order, from the `@UI.selectionField` positions), and a
  table with columns **PR Number**, **Description**, **Requester**, **Cost
  Center**, **Total Amount**, and **Status** (from `@UI.lineItem`). The
  Status column is colored per row, driven by `StatusCriticality`.
- **Create** a new purchase requisition — this opens a draft. `Status`
  comes in as `DRAFT` (`setInitialStatus`) and `Requester` is already
  filled in with your own user (`setRequester`) — you won't see either
  field editable to a different value, since both are `field ( readonly
  )` in the behavior definition.
- **Object Page** — a header status indicator (the `StatusIndicator`
  facet, a `@UI.dataPoint` bound to `StatusCriticality`), then three field
  groups: **General Information** (PR Number, Description, Cost Center,
  Requester, Status), **Amount Information** (Total Amount with its
  currency), and **Approval Information** (Approver, Approved At, Rejection
  Reason) — the last group stays empty until the request is actually
  approved or rejected. Below that, an **Items** table (from the `_Item`
  composition) with columns Item Number, Material, Description, Quantity,
  Price, and Amount.
- **Toolbar buttons** — Submit, Approve, Reject, and Request Info all
  appear, but only **Submit** is clickable on a brand-new draft. This
  isn't a preview quirk — it's `get_instance_features` in
  `ZBP_I_PR_HEADER`: Submit is enabled only while `Status = DRAFT` or
  `Status = INFO_REQ`; Approve, Reject, and Request Info are enabled only
  while `Status = PENDING`.
- Add at least one item — Material, Quantity, and Price are mandatory.
  Watch **Item Number** get assigned automatically (10, 20, 30, ...) and
  **Amount** calculate itself as Quantity × Price; the header's **Total
  Amount** updates right along with it.
- Save (this runs `Prepare`'s three validations and activates the draft),
  then click **Submit**. `Status` becomes `PENDING`, `PR Number` gets
  assigned from the number range, the Submit button disables, and Approve
  / Reject / Request Info all become clickable.
- Try **Approve** — `Status` becomes `APPROVED`, `Approver` and `Approved
  At` fill in, and the status badge turns green. Or try **Reject** — a
  dialog asks for a rejection reason (backed by `ZA_PR_REJECT`); leaving
  it blank is rejected by `validateRejectReason`. Or try **Request Info** —
  `Status` becomes `INFO_REQ`, the badge goes back to a warning color, and
  Submit becomes clickable again.

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "Data source X could not be found" / "not active" when activating a view or behavior definition | Activated an object before something it depends on is active | Re-check the layer order in §1 — database before data model, data model before behavior, behavior before projection, and so on |
| `ZI_PR_ITEM`/`ZI_PR_HEADER` (or `ZC_PR_ITEM`/`ZC_PR_HEADER`) won't activate no matter which one you activate first | The composition/redirected-association pair references each other — a genuine circular dependency, not a mistake | Save both un-activated, multi-select both files, Activate together (§3, §5) |
| Behavior definition activation fails citing `zpr_header_d` or `zpr_item_d` as missing | `with draft;` needs draft tables that don't exist as source files in this project | Place the cursor on the `with draft;` line in `ZI_PR_HEADER.bdef` and run the Quick Fix (`Ctrl+1`) to generate and activate them (§4) |
| Metadata extension won't activate, complains the target view doesn't support extensions | `@Metadata.allowExtensions: true` is missing from the projection view it targets | Confirm `ZC_PR_HEADER.ddls` / `ZC_PR_ITEM.ddls` still carry `@Metadata.allowExtensions: true` — both should, out of the box, in this project |
| Everything activates cleanly, but the Fiori preview says the service can't be found / gives a 404 | The service binding was activated but never published | Open the Service Binding editor and click **Publish**, not just Activate (§8) |
| Status field on the Object Page shows plain text with no color | `StatusCriticality` isn't wired to `@UI.criticality`, or the `CASE` mapping in `ZI_PR_HEADER.ddls` isn't producing the expected 0–3 value | Check that `Status;` in `ZC_PR_HEADER_MDE.ddlx` carries `@UI.dataPoint: { ..., criticality: 'StatusCriticality' }` and that `StatusCriticality` in `ZI_PR_HEADER.ddls` maps DRAFT→0, PENDING/INFO_REQ→2, APPROVED→3, REJECTED→1 |
| Approve / Reject / Request Info buttons stay greyed out | This is almost always the current `Status`, not a bug — `get_instance_features` only enables them while `Status = PENDING` | Submit the draft first; Approve/Reject/Request Info won't enable on a `DRAFT` or `INFO_REQ` record |
| Submit button stays greyed out on a request you expect to still be editable | `get_instance_features` only enables `submit` while `Status = DRAFT` or `Status = INFO_REQ` | If `Status = PENDING`, `APPROVED`, or `REJECTED`, that's expected — Submit is intentionally not available past the point of first submission (except after a Request Info round-trip) |

---

# CDS / OData Kurulum Rehberi — Purchase Requisition Approval

Gerçek bir SAP BTP ABAP Environment / S/4HANA sisteminde, ADT (Eclipse)
üzerinden bu projedeki her nesneyi sıfırdan aktive edip çalışan bir Fiori
Elements önizlemesine ulaştıran, tıklama tıklama eksiksiz bir rehber.
Aşağıda anlatılan her nesne adı, bağımlılık ve davranış doğrudan `src/`
altındaki kaynak dosyalardan geliyor — burada genel geçer bir RAP kontrol
listesi yok.

## 1. Genel bakış

| Katman | Nesneler | Sayı |
|---|---|---|
| Database | `ZPR_HEADER`, `ZPR_ITEM` | 2 tablo |
| Data Model (interface) | `ZI_PR_HEADER`, `ZI_PR_ITEM`, `ZA_PR_REJECT` | 3 view (2 root/child + 1 abstract entity) |
| Behavior | `ZI_PR_HEADER.bdef` (hem `ZI_PR_HEADER` hem `ZI_PR_ITEM` için davranışı tanımlıyor), `ZBP_I_PR_HEADER` | 1 behavior definition + 1 implementasyon sınıfı |
| Projection | `ZC_PR_HEADER`, `ZC_PR_ITEM` (view'lar), `ZC_PR_HEADER.bdef`, `ZC_PR_ITEM.bdef` (behavior) | 2 view + 2 behavior definition |
| Metadata Extension | `ZC_PR_HEADER_MDE`, `ZC_PR_ITEM_MDE` | 2 |
| Service | `ZUI_PR_HEADER` (service definition) + doğrudan sistemde oluşturulan 1 service binding (kaynak dosyası yok) | 1 dosya + 1 binding |

Yani 6 katmana yayılmış 14 kaynak dosyası, artı elle yazmadığın, ADT'nin
senin için ürettiği iki draft tablosu (`zpr_header_d`, `zpr_item_d`) —
bunun detayı 4. adımda.

**Sıranın neden önemli olduğu:** bu zincirdeki her CDS nesnesi, altındaki
nesne cinsinden tanımlanıyor — bir projection view `as projection on
ZI_PR_HEADER` diyor, bir behavior definition `for ZI_PR_HEADER` diyor, bir
metadata extension `annotate view ZC_PR_HEADER` diyor. ADT bu
referansların her birini aktivasyon anında DDIC'e karşı çözüyor, yani
referans edilen nesne henüz yoksa (ya da varsa ama aktif değilse)
aktivasyon "bulunamadı" ya da "aktif değil" hatasıyla başarısız oluyor.
Katmanları bağımlılık sırasına göre ilerlemek — database → data model →
behavior → projection → metadata → service — bunu baştan engelliyor. Bu
projede iki view'ın birbirini referans ettiği iki nokta var (interface
katmanı, projection katmanı), ve bunlar biraz farklı bir yaklaşım
gerektiriyor — bkz. 3. ve 5. adımlar.

**Ön koşullar:**
- Eclipse'e kurulu ABAP Development Tools (ADT) eklentisi.
- SAP BTP ABAP Environment trial/free-tier bir sisteme ya da ABAP Cloud
  geliştirmenin açık olduğu bir S/4HANA sistemine çalışan bir bağlantı.
- DDIC ve RAP nesneleri oluşturma yetkisine sahip bir geliştirici
  kullanıcısı.
- Bunların hepsini tutacak bir ABAP paketi — kişisel bir trial sistemde
  yerel/test paketi (`$TMP` tarzı, transport edilemeyen), ya da paylaşılan
  bir sistemde çalışıyorsan transport edilebilir düzgün bir paket ve
  transport request.

Bu projede Access Control (DCL) nesnesi yok — `src/` altında bir `.dcls`
dosyası bulunmuyor, ve her iki interface view da
`@AccessControl.authorizationCheck: #NOT_REQUIRED` taşıyor, yani bu
konuda aktive edilecek bir şey yok.

## 2. Database tabloları

`ZPR_HEADER` ve `ZPR_ITEM`, düz `define table` DDIC kaynakları. `ZPR_ITEM`,
bir yorum satırında `ZPR_HEADER.pr_uuid`'ye composition bağlantısı olarak
belgelenen bir `parent_uuid` alanı taşıyor, ama tablo DDL'inde gerçek bir
foreign key olarak tanımlı değil — yani iki tablo arasında zorunlu bir
aktivasyon sırası yok, ikisi de tek başına sorunsuz aktive olur. Yine de
sadece okunabilirlik açısından `ZPR_HEADER`'ı önce aktive et, kavramsal
olarak parent olduğu için:

1. Paketinde bir Database Table oluştur (`New > Other ABAP Repository
   Object > Dictionary > Database Table`), adı `ZPR_HEADER`,
   `src/database/ZPR_HEADER.ddls` içeriğini yapıştır, kaydet ve aktive et
   (`Ctrl+F3` ya da Activate araç çubuğu düğmesi).
2. `src/database/ZPR_ITEM.ddls` ile `ZPR_ITEM` için aynısını tekrarla.

## 3. Data model (interface) view'ları

`ZA_PR_REJECT` bir abstract entity (`SELECT` yok, persistence yok — sadece
tek bir `reject_reason` alanı) ve bu katmandaki hiçbir şeye bağımlı değil.
4. adımdaki behavior definition onu `action reject parameter
ZA_PR_REJECT` olarak referans etmeden önce, uygun olduğun herhangi bir
zamanda oluşturup aktive edebilirsin.

`ZI_PR_HEADER` ve `ZI_PR_ITEM` **birbirini** referans ediyor ve tek tek
aktive edilemiyor:

- `ZI_PR_HEADER`, `composition [0..*] of ZI_PR_ITEM as _Item` tanımlıyor.
- `ZI_PR_ITEM`, `association to parent ZI_PR_HEADER as _Header`
  tanımlıyor.

Önce `ZI_PR_HEADER`'ı oluşturup aktive etmeyi denersen, ADT `ZI_PR_ITEM`
henüz yok diye şikayet eder; önce `ZI_PR_ITEM`'ı denersen, bu sefer
`ZI_PR_HEADER` yok diye şikayet eder. Hiçbir sıra tek başına işe yaramıyor.
Bunu aşmanın yolu:

1. İki view entity'yi de oluştur (`New > Other ABAP Repository Object >
   Core Data Services > Data Definition`), sırasıyla
   `src/data-model/ZI_PR_HEADER.ddls` ve
   `src/data-model/ZI_PR_ITEM.ddls` içeriğini yapıştır, ve **ikisini de
   henüz hiçbirini aktive etmeden kaydet**.
2. Project Explorer'da ikisini birlikte seç (`Ctrl` ile çoklu seçim),
   sağ tıkla ve **Activate**'i seç. ADT iki aktivasyonu tek bir işlemde
   toplu olarak yapıyor ve karşılıklı referansı orada çözüyor — döngüsel
   bir RAP composition çiftini ayağa kaldırmanın standart yolu bu.

## 4. Behavior definition + implementasyon sınıfı

`ZI_PR_HEADER.bdef`, `managed implementation in class zbp_i_pr_header
unique;` ile açılıyor ve aynı dosya içinde hem `ZI_PR_HEADER` (alias
`PurchaseRequisition`) hem `ZI_PR_ITEM` (alias
`PurchaseRequisitionItem`) için davranışı tanımlıyor — tek bir behavior
definition kaynağı, tüm root/child çiftini kapsıyor.

1. `ZI_PR_HEADER` ve `ZI_PR_ITEM` aktifken, `ZI_PR_HEADER` üzerinde yeni
   bir Behavior Definition oluştur (`New > Other ABAP Repository Object >
   Core Data Services > Behavior Definition`), `src/behavior/ZI_PR_HEADER.bdef`
   içeriğini yapıştır, kaydet.
2. ADT, `zbp_i_pr_header`'ı henüz var olmayan bir implementasyon sınıfı
   olarak işaretleyecek. İmleci `implementation in class
   zbp_i_pr_header` satırına koy ve sınıf iskeletini üretmek için Quick
   Fix (`Ctrl+1`) kullan — bu, `FOR BEHAVIOR OF zi_pr_header` olarak zaten
   bağlanmış `ZBP_I_PR_HEADER`'ı oluşturur.
3. Üretilen sınıfı aç ve içeriğini `src/behavior/ZBP_I_PR_HEADER.clas.abap`
   ile değiştir (determination'lar, validation'lar, action'lar,
   `get_instance_features`, `get_instance_authorizations`
   implementasyonları). Sınıfı aktive et.
4. Behavior definition'ı aktive et.

**Draft tabloları — gerekli bir ek adım.** `ZI_PR_HEADER.bdef`, `with
draft;` içeriyor, ve behavior definition `draft table zpr_header_d` ile
`draft table zpr_item_d`'yi adlandırıyor. Bu iki tablo bu projede hiçbir
yerde kaynak dosya olarak bulunmuyor, `src/database/` altında da
bulamazsın — bunlar elle yazılmak yerine ADT tarafından üretilmek üzere
tasarlandı. Behavior definition'ı aktive ettiğinde (ya da `with draft;`
yazıp kaydettiğin an), ADT her iki draft tablosunu da eksik olarak
bildirecek. İmleci doğrudan `with draft;` satırına koy ve Quick Fix'i
(`Ctrl+1`) tetikle; bu, `ZPR_HEADER`/`ZPR_ITEM` ile RAP'in kendi draft
yönetim alanlarından otomatik olarak şekillendirilmiş `zpr_header_d` ve
`zpr_item_d`'yi üretip aktive etmeyi öneriyor. Behavior definition'ın
kendisini aktive etmeden önce bunu yap, yoksa aktivasyon eksik draft
tablolarında başarısız olur.

## 5. Projection katmanı

İki projection view, tıpkı interface view'ların yaptığı gibi birbirini
referans ediyor, sadece orijinal composition/to-parent çifti yerine
redirected association'larla:

- `ZC_PR_HEADER`, `as projection on ZI_PR_HEADER as PurchaseRequisition`
  ve composition'ı yönlendiriyor: `_Item : redirected to composition
  child ZC_PR_ITEM`.
- `ZC_PR_ITEM`, `as projection on ZI_PR_ITEM as PurchaseRequisitionItem`
  ve to-parent association'ı yönlendiriyor: `_Header : redirected to
  parent ZC_PR_HEADER`.

Aynı döngüsel referans, aynı çözüm:

1. `ZI_PR_HEADER` / `ZI_PR_ITEM` üzerinde projection view'lar olarak
   `ZC_PR_HEADER` ve `ZC_PR_ITEM`'ı oluştur,
   `src/projection/ZC_PR_HEADER.ddls` ve
   `src/projection/ZC_PR_ITEM.ddls`'i yapıştır, ikisini de aktive etmeden
   kaydet.
2. İkisini birlikte seç ve tıpkı 3. adımdaki gibi birlikte aktive et.

İkisi de `@Metadata.allowExtensions: true` taşıyor — 6. adımın ihtiyaç
duyduğu şey bu.

Projection view'lar aktifken, iki projection behavior definition'ı aktive
et. View'ların aksine, `ZC_PR_HEADER.bdef` ve `ZC_PR_ITEM.bdef` birbirinin
ABAP söz dizimini doğrudan referans etmiyor (aralarındaki association
zaten CDS view seviyesinde çözülmüş durumda), yani burada döngüsel bir
aktivasyon sorunu yok — eşleşen projection view ve kök behavior definition
(`ZI_PR_HEADER.bdef`) zaten aktif olduğu sürece, hangi sırayla
aktive edersen et:

1. `ZC_PR_ITEM` üzerinde bir Behavior Definition oluştur (`projection;`),
   `src/projection/ZC_PR_ITEM.bdef`'i yapıştır, aktive et.
2. `ZC_PR_HEADER` üzerinde bir Behavior Definition oluştur (`projection;
   strict ( 2 ); use draft;`), `src/projection/ZC_PR_HEADER.bdef`'i
   yapıştır, aktive et.

## 6. Metadata extension'lar

`ZC_PR_HEADER_MDE` (`annotate view ZC_PR_HEADER with { ... }`) ve
`ZC_PR_ITEM_MDE` (`annotate view ZC_PR_ITEM with { ... }`), her biri bir
projection view'ı genişletiyor. Hedef view'ların ikisi de zaten
`@Metadata.allowExtensions: true` taşıyor, ki bu zorunlu bir gereksinim —
bunu deklare etmeyen bir view'a karşı bir metadata extension aktive
olamaz. İki extension dosyası birbirini referans etmiyor, yani aralarında
sıra önemli değil:

1. `ZC_PR_HEADER` üzerinde bir Metadata Extension oluştur (`New > Other
   ABAP Repository Object > Core Data Services > Metadata Extension`),
   `src/metadata/ZC_PR_HEADER_MDE.ddlx`'i yapıştır, aktive et.
2. `ZC_PR_ITEM` üzerinde bir Metadata Extension oluştur,
   `src/metadata/ZC_PR_ITEM_MDE.ddlx`'i yapıştır, aktive et.

## 7. Service definition

`ZUI_PR_HEADER.srvd`, tam olarak bir view açıyor:

```
define service ZUI_PR_HEADER {
  expose ZC_PR_HEADER as PurchaseRequisition;
}
```

`ZC_PR_ITEM` burada listelenmiyor ve kendi entity set'i yok — sadece
zaten kendisine yönlendirilmiş olan `ZC_PR_HEADER`'ın `_Item`
composition'ı üzerinden erişilebiliyor. Daha sonra service binding'de ve
Fiori önizlemesinde göreceğin entity set'in adı `ZC_PR_HEADER` değil,
`PurchaseRequisition`.

1. `ZC_PR_HEADER` üzerinde bir Service Definition oluştur (`New > Other
   ABAP Repository Object > Core Data Services > Service Definition`),
   `src/service/ZUI_PR_HEADER.srvd`'yi yapıştır, aktive et.

## 8. Service binding

Service binding için bir kaynak dosyası yok — 
[src/service/README.md](../src/service/README.md)'de belgelendiği gibi,
bu görsel olarak oluşturduğun bir ADT nesnesi, yazıp yapıştıracağın bir
şey değil. `src/` altında bu adımı kapsayan hiçbir şey yok; bunu doğrudan
ADT'de yap:

1. `ZUI_PR_HEADER`'a sağ tıkla → `New > Service Binding`.
2. Bir isim ve açıklama ver (örn. `ZUI_PR_HEADER_O4`), ve **Binding
   Type**'ı **OData V4 - UI** olarak ayarla. Service definition alanı
   zaten `ZUI_PR_HEADER`'ı göstermeli.
3. Wizard'ı bitir — bu, Service Binding editörünü açar. **Activate**'e
   tıkla.
4. **Publish**'e tıkla. Bu, insanların en sık atladığı adım, ve altındaki
   her nesne sorunsuz aktive olmasına rağmen yeni yayınlanan bir
   servisin "çalışmamasının" en yaygın tek sebebi: bir service binding'i
   aktive etmek onu sadece yerel olarak var eder, publish etmek ise onu
   runtime'ın servis kataloğuna kaydederek gerçekten çağrılabilir hale
   getirir. Önizlemeyi denediğinde `PurchaseRequisition` görünmüyorsa,
   önce buraya geri dön.

## 9. Fiori Elements uygulamasını önizleme

Service Binding editöründen `PurchaseRequisition` entity set'ini seç ve
**Preview**'e tıkla. `ZC_PR_HEADER_MDE.ddlx` ve `ZC_PR_ITEM_MDE.ddlx`
içindeki annotation'lara göre şunları görmen gerekiyor:

- **List Report** — **Requester**, **Status** ve **Cost Center** filtre
  çubuğu (bu sırayla, `@UI.selectionField` pozisyonlarından), ve **PR
  Number**, **Description**, **Requester**, **Cost Center**, **Total
  Amount**, **Status** kolonlu bir tablo (`@UI.lineItem`'dan). Status
  kolonu, `StatusCriticality`'nin belirlediği şekilde satır bazında
  renkli.
- **Create** ile yeni bir satın alma talebi — bu bir draft açar. `Status`
  `DRAFT` olarak geliyor (`setInitialStatus`) ve `Requester` zaten kendi
  kullanıcınla dolu geliyor (`setRequester`) — ikisini de farklı bir
  değere düzenleyemezsin, çünkü behavior definition'da ikisi de `field (
  readonly )`.
- **Object Page** — bir header status göstergesi (`StatusIndicator`
  facet'i, `StatusCriticality`'ye bağlı bir `@UI.dataPoint`), ardından üç
  field group: **General Information** (PR Number, Description, Cost
  Center, Requester, Status), **Amount Information** (para birimiyle
  birlikte Total Amount), ve **Approval Information** (Approver, Approved
  At, Rejection Reason) — bu son grup, talep gerçekten onaylanana ya da
  reddedilene kadar boş kalır. Onun altında, `_Item` composition'ından
  gelen, Item Number, Material, Description, Quantity, Price ve Amount
  kolonlu bir **Items** tablosu.
- **Toolbar butonları** — Submit, Approve, Reject ve Request Info hepsi
  görünür, ama yepyeni bir draft üzerinde sadece **Submit** tıklanabilir.
  Bu bir önizleme tuhaflığı değil — `ZBP_I_PR_HEADER`'daki
  `get_instance_features`'ın kendisi: Submit sadece `Status = DRAFT` ya
  da `Status = INFO_REQ` iken aktif; Approve, Reject ve Request Info
  sadece `Status = PENDING` iken aktif.
- En az bir item ekle — Material, Quantity ve Price zorunlu. **Item
  Number**'ın otomatik atandığını (10, 20, 30, ...) ve **Amount**'un
  Quantity × Price olarak kendiliğinden hesaplandığını gözlemle;
  header'ın **Total Amount**'u da bununla birlikte güncelleniyor.
- Kaydet (bu, `Prepare`'in üç validation'ını çalıştırır ve draft'ı aktive
  eder), sonra **Submit**'e tıkla. `Status`, `PENDING` oluyor, `PR
  Number` number range'den atanıyor, Submit butonu pasifleşiyor, Approve
  / Reject / Request Info hepsi tıklanabilir hale geliyor.
- **Approve**'u dene — `Status`, `APPROVED` oluyor, `Approver` ve
  `Approved At` doluyor, status rozeti yeşile dönüyor. Ya da **Reject**'i
  dene — bir gerekçe (`ZA_PR_REJECT` destekli) isteyen bir diyalog
  açılıyor; boş bırakmak `validateRejectReason` tarafından reddediliyor.
  Ya da **Request Info**'yu dene — `Status`, `INFO_REQ` oluyor, rozet
  tekrar uyarı rengine dönüyor, Submit tekrar tıklanabilir hale geliyor.

## 10. Sorun giderme

| Belirti | Sebep | Çözüm |
|---|---|---|
| Bir view ya da behavior definition aktive edilirken "Data source X bulunamadı" / "aktif değil" | Bağımlı olduğu bir şey aktif olmadan bir nesne aktive edilmeye çalışıldı | §1'deki katman sırasını tekrar kontrol et — database'den önce data model, data model'den önce behavior, behavior'dan önce projection, ve böyle devam |
| `ZI_PR_ITEM`/`ZI_PR_HEADER` (ya da `ZC_PR_ITEM`/`ZC_PR_HEADER`) hangisini önce aktive edersen et aktive olmuyor | Composition/redirected-association çifti birbirini referans ediyor — bu bir hata değil, gerçek bir döngüsel bağımlılık | İkisini de aktive etmeden kaydet, ikisini birlikte seç, birlikte Activate et (§3, §5) |
| Behavior definition aktivasyonu `zpr_header_d` ya da `zpr_item_d`'yi eksik diye gösteriyor | `with draft;`, bu projede kaynak dosya olarak bulunmayan draft tablolarına ihtiyaç duyuyor | İmleci `ZI_PR_HEADER.bdef`'teki `with draft;` satırına koy ve bunları üretip aktive etmek için Quick Fix'i (`Ctrl+1`) çalıştır (§4) |
| Metadata extension aktive olmuyor, hedef view'ın extension'ları desteklemediğinden şikayet ediyor | Hedeflediği projection view'da `@Metadata.allowExtensions: true` eksik | `ZC_PR_HEADER.ddls` / `ZC_PR_ITEM.ddls`'in hâlâ `@Metadata.allowExtensions: true` taşıdığını doğrula — bu projede ikisi de, kutudan çıktığı gibi, taşımalı |
| Her şey sorunsuz aktive oluyor, ama Fiori önizlemesi servisin bulunamadığını söylüyor / 404 veriyor | Service binding aktive edildi ama hiç publish edilmedi | Service Binding editörünü aç ve sadece Activate değil, **Publish**'e tıkla (§8) |
| Object Page'deki Status alanı renksiz, düz metin olarak görünüyor | `StatusCriticality`, `@UI.criticality`'ye bağlanmamış, ya da `ZI_PR_HEADER.ddls`'teki `CASE` eşlemesi beklenen 0-3 değerini üretmiyor | `ZC_PR_HEADER_MDE.ddlx`'teki `Status;`'in `@UI.dataPoint: { ..., criticality: 'StatusCriticality' }` taşıdığını, `ZI_PR_HEADER.ddls`'teki `StatusCriticality`'nin DRAFT→0, PENDING/INFO_REQ→2, APPROVED→3, REJECTED→1 eşlemesini yaptığını kontrol et |
| Approve / Reject / Request Info butonları gri kalıyor | Bu neredeyse her zaman bir bug değil, güncel `Status` — `get_instance_features` bunları sadece `Status = PENDING` iken aktif ediyor | Önce draft'ı submit et; Approve/Reject/Request Info bir `DRAFT` ya da `INFO_REQ` kayıtta aktif olmayacak |
| Hâlâ düzenlenebilir olmasını beklediğin bir talepte Submit butonu gri kalıyor | `get_instance_features`, `submit`'i sadece `Status = DRAFT` ya da `Status = INFO_REQ` iken aktif ediyor | `Status` `PENDING`, `APPROVED` ya da `REJECTED` ise bu beklenen bir durum — Submit, ilk gönderim noktasından sonra (bir Request Info gidiş-dönüşü hariç) bilinçli olarak kullanılamıyor |