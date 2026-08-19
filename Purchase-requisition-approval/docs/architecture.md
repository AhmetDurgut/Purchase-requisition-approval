# Technical Architecture — Purchase Requisition Approval

## 1. Why it's built this way

The guiding idea behind managed RAP's layered architecture — interface → projection → metadata extension → service — is to keep reusable business logic in one place and everything that's specific to a particular service or a particular UI in another. A behavior definition built on the interface view should work no matter who's consuming it; a Fiori annotation should never have to leak down into the layer that actually enforces the business rules. This project follows that split deliberately, and one part of it was learned the hard way rather than known in advance.

- **Two CDS views, not one** — `ZI_PR_HEADER` (interface) and `ZC_PR_HEADER` (projection) look almost identical on paper, and it's tempting to ask why the projection isn't just the interface exposed directly. The answer is that they serve different jobs: `ZI_PR_HEADER` is where the composition, the associations, and the semantics live — the layer any future consumer, batch job, or second UI would build on — while `ZC_PR_HEADER` is the one specific consumption path this app actually uses, and it's the only layer that's allowed to know anything about Fiori.
- **The UI-annotation mistake, and the fix** — that split wasn't just theoretical here. Early in the build, the `@UI.*` annotations for the status indicator and the field groups were attached directly to `ZI_PR_HEADER` in a metadata extension targeting the interface view. It activated, and it even rendered — but it's not where SAP's own guidance says UI information belongs, since the interface view isn't supposed to know it's being shown on a screen at all. It was moved to a metadata extension targeting `ZC_PR_HEADER` instead (`ZC_PR_HEADER_MDE`), which is why both `ZI_PR_HEADER.ddls` and `ZC_PR_HEADER.ddls` carry `@Metadata.allowExtensions: true` — the interface view keeps the flag for structural reasons, but the annotations that actually matter for the Object Page live only on the projection.
- **Draft-enabled managed RAP** — `with draft;` in `ZI_PR_HEADER.bdef` exists so a requester can fill in half a requisition, save it, and come back later without losing anything and without a single line of hand-written persistence code. ADT generates the draft tables (`zpr_header_d`, `zpr_item_d`) automatically the moment the behavior definition is activated — they're not something anyone had to design or write a `DEFINE TABLE` for.
- **The determine-action pattern for `calculateTotal`** — this is the one genuinely non-obvious RAP pattern in the project, and it came out of a real dead end during development. `TotalAmount` is `field ( readonly )`, and the natural first instinct was a determination triggered `on modify { field TotalAmount; }` — except a readonly field can never be the field a user's change triggers on, so that determination could never fire on its own. The fix was to keep `calculateTotal` as a determination but wrap a second entry point, the determine action `recalcTotal`, around it with `determination ( always ) calculateTotal`, and then call that action explicitly with EML `EXECUTE` from `calculateItemAmount` every time an item's `Quantity` or `Price` changes. The header total is recalculated exactly when it needs to be, without ever being something a determination watches on its own trigger field.
- **Config-free, single-object simplicity** — this project doesn't split validation, determination, and action logic across a checker/logger/notifier-style set of classes the way a scoring engine would. Everything lives in one behavior implementation class, `ZBP_I_PR_HEADER`. That's not an oversight — an approval workflow doesn't have a "sensitivity" or a set of tunable weights the way a risk engine does; the rules here (a description and cost center are mandatory, a rejection needs a reason, an amount has to be positive) are fixed business rules, not something anyone would want to retune from a config table, so there was nothing to gain from splitting them across files that would all still need each other to make sense.

## 2. Who does what

| Object | Layer | Responsibility |
|---|---|---|
| `ZPR_HEADER` / `ZPR_ITEM` | Database | Persistence tables for header and item. Technical keys are UUIDs (`pr_uuid`, `item_uuid`); `pr_number` is the human-readable business key, left blank until a determination assigns it. Carry the admin fields (`created_by/at`, `last_changed_by/at`, `local_last_changed_at`) managed RAP needs for concurrency control. |
| `ZI_PR_HEADER` / `ZI_PR_ITEM` | Data Model (interface) | Root and child interface views — the reusable business-logic layer. Define the composition (`_Item`) and the mandatory to-parent association (`_Header`), expose the admin fields with `@Semantics` annotations, and compute `StatusCriticality` on the header. |
| `ZA_PR_REJECT` | Data Model (abstract entity) | Parameter structure for the `reject` action — a single `reject_reason` field, no persistence of its own, used only so RAP can render the rejection-reason input dialog in Fiori. |
| `ZBP_I_PR_HEADER` | Behavior (implementation) | The one behavior implementation class for the whole BO: five determinations on the header, three on the item, three validations, four actions (`submit`/`approve`/`reject`/`requestInfo`), the determine action `recalcTotal`, `get_instance_features`, and `get_instance_authorizations`. |
| `ZC_PR_HEADER` / `ZC_PR_ITEM` | Projection | Consumption views and projection behavior definitions. Redirect the composition/to-parent association to each other, re-expose the actions and draft handling the UI needs, and carry `@Metadata.allowExtensions: true` so the metadata extensions below attach here rather than to the interface views. |
| `ZC_PR_HEADER_MDE` / `ZC_PR_ITEM_MDE` | Metadata Extension | Fiori Elements UI annotations — facets, field groups, line items, the status `@UI.dataPoint`/`@UI.criticality`, and the header toolbar buttons for submit/approve/reject/requestInfo. |
| `ZUI_PR_HEADER` | Service | Service definition exposing `ZC_PR_HEADER` as `PurchaseRequisition`. `ZC_PR_ITEM` is reached only through the `_Item` composition — it's never exposed on its own. |

## 3. How a request flows through it

**Create → Draft → Submit:**

```
Fiori Elements app: user clicks "Create"
    │
    ▼
new draft instance created
    │
    ├─ determination setInitialStatus on modify { create; }  → Status = DRAFT
    ├─ determination setRequester on modify { create; }      → Requester = current user
    │                                                           (cl_abap_context_info=>get_user_technical_name)
    ▼
user fills in Description, CostCenter, adds line items
    │
    ▼
for each new item (association _Item { create; with draft; }):
    ├─ determination setItemNumber on modify { create; }
    │        → next number among sibling items of the same header, +10 increment (10, 20, 30, ...)
    ├─ determination setItemCurrency on modify { create; }
    │        → Currency copied from the parent header
    └─ determination calculateItemAmount on modify { field Quantity, Price; }
             ├─ Amount = Quantity * Price
             └─ EXECUTE recalcTotal on the parent header (EML, called explicitly)
                       └─ determination calculateTotal (always)  → TotalAmount = SUM(item Amount)
    │
    ▼
draft determine action Prepare  (runs automatically before Activate)
    ├─ validation validateAmount        → TotalAmount must be > 0
    ├─ validation validateItems         → at least one item is required
    └─ validation validateRejectReason  → only fires once Status = REJECTED
    │
    ▼
draft action Activate optimized  → draft becomes the active instance
    │
    ▼
user clicks "Submit"  (action submit, enabled only while Status = DRAFT or INFO_REQ)
    │
    ▼
ZBP_I_PR_HEADER=>submit  → Status = PENDING
    │
    ▼
determination setPRNumber on modify { field Status; }
    └─ only when PrNumber IS INITIAL
          → cl_numberrange_runtime=>number_get( object = 'ZPR_RANGE', nr_range_nr = '01' )
```

**Approval flow:**

```
Status = PENDING
    │
    ▼
get_instance_features (ZBP_I_PR_HEADER)
    ├─ %action-submit       → disabled  (already submitted)
    ├─ %action-approve      → enabled
    ├─ %action-reject       → enabled
    └─ %action-requestInfo  → enabled
    │
    ▼
approver opens the Object Page and picks one:

    ├─ "Approve"  → action approve
    │        ▼
    │    ZBP_I_PR_HEADER=>approve  → Status = APPROVED
    │        ▼
    │    determination setApprovalData on modify { field Status; }
    │        └─ only when Status = APPROVED and Approver IS INITIAL
    │              → Approver = current user, ApprovedAt = utclong_current( )
    │
    ├─ "Reject"  → action reject parameter ZA_PR_REJECT
    │        ▼
    │    ZBP_I_PR_HEADER=>reject  → Status = REJECTED, RejectReason = %param-reject_reason
    │        ▼
    │    validation validateRejectReason on save { field Status, RejectReason; }
    │        └─ blocks the save if Status = REJECTED and RejectReason is still empty
    │
    └─ "Request Info"  → action requestInfo
             ▼
         ZBP_I_PR_HEADER=>requestInfo  → Status = INFO_REQ
             ▼
         get_instance_features re-evaluates: %action-submit is enabled again,
         so the requester can edit and resubmit
```

## 4. Key design decisions

- **Status flow and instance feature control** — the request moves through five states: `DRAFT` → `PENDING` → `APPROVED` / `REJECTED` / `INFO_REQ`. Rather than leaving it to the UI to guess which button makes sense, `get_instance_features` reads each instance's current `Status` and switches every action's enabled/disabled state explicitly: `submit` is enabled only when `Status = DRAFT` or `Status = INFO_REQ`; `approve`, `reject`, and `requestInfo` are all enabled only when `Status = PENDING`, and disabled everywhere else. That's the entire mechanism that makes it impossible to, say, approve a draft — there's no separate check inside `approve` itself for that, because the button is never clickable in the first place.
- **Item numbering** — `setItemNumber` assigns each new item its `ItemNumber` on create. It reads the sibling items of the same header through the `_Item` association, finds the current highest number among them, and adds 10 (so items land on 10, 20, 30, …, leaving room to insert between them later the way classic SAP documents do). Because RAP can hand a determination several new items belonging to the same header in one call — someone adding three lines in a single save — the method first collapses the incoming keys down to one entry per distinct header (`distinct_headers`) before it computes the starting number, so three items created together get consecutive numbers instead of all landing on the same value.
- **Currency inheritance** — `setItemCurrency` runs on create and copies the parent header's `Currency` onto the new item, read through the `_Header` association. This is what guarantees `Price` and `Amount` on every item are always denominated the same way as `TotalAmount` on the header — there's no path through the UI or the API where an item can end up with a currency the header doesn't share.
- **Number range for `PrNumber`** — `setPRNumber` draws the human-readable requisition number from number range object `ZPR_RANGE` (range `01`) via `cl_numberrange_runtime=>number_get`. It only does this for instances where `Status = PENDING` and `PrNumber IS INITIAL` — the emptiness check matters as much as the status check, because without it, submitting a request that gets sent back with `requestInfo` and resubmitted would draw a second number and silently orphan the first one.
- **Instance authorization is a placeholder** — `get_instance_authorizations` currently returns `if_abap_behv=>auth-allowed` unconditionally for `%update`, `%delete`, and all four actions. That's intentional, documented here the same way this portfolio's other projects document their own missing authority checks: this is a portfolio project with no real authorization object or PFCG role behind it, so there is nothing meaningful to check against yet. A real rollout would replace this with an `AUTHORITY-CHECK` (or a proper RAP authorization check) tied to the requester's or approver's role, most naturally scoped by cost center or organizational unit.

## 5. The CDS/database layer

- **`ZPR_HEADER`** carries the technical key `pr_uuid`, the business key `pr_number`, the descriptive/organizational fields (`description`, `requester`, `cost_center`), the amount pair `total_amount`/`currency`, the workflow field `status`, the approval fields `approver`/`approved_at`/`reject_reason`, and the standard admin fields RAP needs (`created_by`/`created_at`, `last_changed_by`/`last_changed_at` as the total ETag, `local_last_changed_at` for optimistic concurrency). **`ZPR_ITEM`** mirrors that shape at line-item level: `item_uuid` as the technical key, `parent_uuid` as the to-parent link, `item_number` as the business-visible line number, `material`/`description`/`quantity`/`unit`, the amount pair `price`/`amount` plus its own `currency`, and the same admin fields as the header.
- **`StatusCriticality`** is a computed field on `ZI_PR_HEADER`, not a stored column — a `CASE` expression that maps the free-text `Status` value to a 0–3 Fiori criticality code (`0` none for `DRAFT`, `2` warning for `PENDING`/`INFO_REQ`, `3` positive for `APPROVED`, `1` negative for `REJECTED`). It exists purely because `@UI.criticality` in the metadata extension needs to bind to a numeric field with SAP's fixed criticality semantics — it can't switch on an arbitrary string like `'APPROVED'` itself — so this field's only job is to give the status indicator on the Object Page something it can actually color by.

## 6. What's simplified on purpose

- **No draft table source files** — `zpr_header_d` and `zpr_item_d`, named in `ZI_PR_HEADER.bdef` as `draft table zpr_header_d` / `draft table zpr_item_d`, don't exist as files anywhere in this repository. That's correct, not missing: ADT generates them automatically (via the Quick Fix offered directly on the `with draft;` line) the moment the behavior definition activates, and their structure is derived entirely from the persistent tables plus RAP's own draft administration fields. There's nothing to hand-write and nothing to check in.
- **No config table, no scoring/weighting logic** — the business rules here (a description and cost center are mandatory, at least one item is required, the total must be positive, a rejection needs a reason) are expressed directly as `field ( mandatory )` declarations and `validation` methods in the behavior definition and `ZBP_I_PR_HEADER`, not externalized to a maintenance table. An approval workflow doesn't have a tunable "sensitivity" the way a risk-scoring engine does — there's no threshold anyone would want to retune without also changing what the rule actually means — so there was no reason to add a table and a class to read it.
- **Permissive instance authorization** — see §4. `get_instance_authorizations` grants every requested operation unconditionally; it's a placeholder for a real authorization object this portfolio project doesn't have behind it.
- **Only `ZC_PR_HEADER` is exposed as a service** — `ZUI_PR_HEADER` exposes `ZC_PR_HEADER` alone. `ZC_PR_ITEM` is reachable only through the header's `_Item` composition, since this app has no scenario where a user would need to browse or query items on their own, outside the requisition they belong to.

## 7. Possible extensions

- **A real authorization object** — tied to the requester's or approver's organizational unit, or to the cost center on the request itself, replacing the permissive placeholder in `get_instance_authorizations`.
- **Workflow integration** — routing the approval step through SAP Business Workflow instead of a flat `approve`/`reject`/`requestInfo` action set, so approvals could be delegated, escalated, or routed by amount without hardcoding that logic into the behavior class.
- **ABAP Unit tests** — the determinations and validations are natural candidates: `calculateItemAmount` and `calculateTotal` are simple input-to-output calculations, `setItemNumber`'s numbering logic has clear edge cases (first item, multiple items created together), and each validation method has an obvious pass/fail boundary to assert against.
- **Multiple approval levels** — requiring a second approver above a configurable `TotalAmount` threshold, which would mean extending the status model (an intermediate "partially approved" state) and adding one more determination to decide whether a given approval is the last one needed.

---

# Teknik Mimari — Purchase Requisition Approval

## 1. Neden bu şekilde kurgulandı

Managed RAP'in katmanlı mimarisinin — interface → projection → metadata extension → service — arkasındaki temel fikir, yeniden kullanılabilir iş mantığını tek bir yerde tutup, belirli bir servise ya da belirli bir arayüze özgü her şeyi ayrı bir yerde tutmak. Interface view üzerine kurulu bir behavior definition, onu kim tüketirse tüketsin çalışabilmeli; bir Fiori annotation'ı ise hiçbir zaman iş kurallarını gerçekten uygulayan katmana sızmamalı. Bu proje bu ayrımı bilinçli olarak takip ediyor, ve bunun bir kısmı önceden bilinen bir kural olarak değil, geliştirme sırasında yaşanarak öğrenildi.

- **Tek değil, iki CDS view** — `ZI_PR_HEADER` (interface) ile `ZC_PR_HEADER` (projection) kağıt üzerinde neredeyse birebir aynı görünüyor, ve "projection'ı doğrudan interface'i dışarı açan bir şey yapmasak olmaz mıydı" diye sormak cazip geliyor. Cevap, ikisinin farklı işlere hizmet etmesi: `ZI_PR_HEADER`, composition'ın, association'ların ve semantic bilgilerin yaşadığı yer — gelecekte başka bir tüketici, bir batch job ya da ikinci bir UI olsa üzerine inşa edeceği katman — `ZC_PR_HEADER` ise bu uygulamanın fiilen kullandığı tek tüketim yolu, ve Fiori hakkında herhangi bir şey bilmesine izin verilen tek katman.
- **UI annotation hatası, ve düzeltilmesi** — bu ayrım burada sadece teoride kalmadı. Geliştirmenin erken bir aşamasında, status göstergesi ve field group'lar için `@UI.*` annotation'ları doğrudan `ZI_PR_HEADER`'ı hedefleyen bir metadata extension'a eklenmişti. Aktive oldu, hatta ekrana da geldi — ama SAP'ın kendi rehberliğinin UI bilgisinin durması gerektiğini söylediği yer orası değil, çünkü interface view'ın bir ekranda gösterildiğini bilmesi hiç beklenmiyor. Bunun yerine `ZC_PR_HEADER`'ı hedefleyen bir metadata extension'a (`ZC_PR_HEADER_MDE`) taşındı — hem `ZI_PR_HEADER.ddls` hem `ZC_PR_HEADER.ddls`'in `@Metadata.allowExtensions: true` taşımasının sebebi de bu: interface view bu flag'i yapısal nedenlerle koruyor, ama Object Page için asıl önemli olan annotation'lar sadece projection'da yaşıyor.
- **Draft destekli managed RAP** — `ZI_PR_HEADER.bdef` içindeki `with draft;`, bir talep edenin bir talebi yarım doldurup kaydedebilmesi ve daha sonra hiçbir şey kaybetmeden, tek bir satır elle yazılmış persistence kodu olmadan geri dönüp tamamlayabilmesi için var. ADT, behavior definition aktive edildiği anda draft tablolarını (`zpr_header_d`, `zpr_item_d`) otomatik olarak üretiyor — kimsenin tasarlaması ya da bir `DEFINE TABLE` yazması gereken bir şey değil bunlar.
- **`calculateTotal` için determine-action deseni** — bu projedeki gerçekten alışılmadık tek RAP deseni, ve geliştirme sırasında yaşanan gerçek bir çıkmazdan doğdu. `TotalAmount`, `field ( readonly )` olarak tanımlı, ve ilk doğal içgüdü `on modify { field TotalAmount; }` ile tetiklenen bir determination yazmaktı — ama salt okunur bir alan, kullanıcının değiştirdiği ve bir tetikleme yaratan alan asla olamıyor, dolayısıyla bu determination kendi başına asla çalışamıyordu. Çözüm, `calculateTotal`'ı bir determination olarak tutup etrafına ikinci bir giriş noktası, `determination ( always ) calculateTotal` içeren determine action `recalcTotal`'ı sarmak, ve bir item'ın `Quantity` ya da `Price`'ı her değiştiğinde `calculateItemAmount`'tan bu action'ı EML `EXECUTE` ile açıkça çağırmak oldu. Header toplamı, kendi tetikleme alanını izleyen bir determination olmadan, tam olarak gerektiği anda yeniden hesaplanıyor.
- **Config'siz, tek nesneli sadelik** — bu proje, bir risk motoru gibi doğrulama, determination ve action mantığını checker/logger/notifier tarzı bir sınıf setine bölmüyor. Her şey tek bir behavior implementasyon sınıfında, `ZBP_I_PR_HEADER`'da yaşıyor. Bu bir eksiklik değil — bir onay iş akışının, bir risk motorunun sahip olduğu türden bir "hassasiyet"i ya da ayarlanabilir ağırlıkları yok; buradaki kurallar (açıklama ve maliyet merkezi zorunlu, bir ret gerekçe gerektiriyor, tutar pozitif olmalı) sabit iş kuralları, kimsenin bir config tablosundan yeniden ayarlamak isteyeceği bir şey değil — dolayısıyla bunları, birbirine zaten ihtiyaç duyacak dosyalara bölmekten kazanılacak bir şey yoktu.

## 2. Kim ne yapıyor

| Nesne | Katman | Sorumluluk |
|---|---|---|
| `ZPR_HEADER` / `ZPR_ITEM` | Database | Header ve item için persistence tabloları. Teknik anahtarlar UUID (`pr_uuid`, `item_uuid`); `pr_number` okunabilir iş anahtarı, bir determination onu atayana kadar boş kalıyor. Managed RAP'in concurrency kontrolü için ihtiyaç duyduğu admin alanlarını (`created_by/at`, `last_changed_by/at`, `local_last_changed_at`) taşıyor. |
| `ZI_PR_HEADER` / `ZI_PR_ITEM` | Data Model (interface) | Root ve child interface view'ları — yeniden kullanılabilir iş mantığı katmanı. Composition'ı (`_Item`) ve zorunlu to-parent association'ı (`_Header`) tanımlıyor, admin alanlarını `@Semantics` annotation'larıyla açıyor, header üzerinde `StatusCriticality`'i hesaplıyor. |
| `ZA_PR_REJECT` | Data Model (abstract entity) | `reject` action'ının parametre yapısı — tek bir `reject_reason` alanı, kendine ait bir persistence'ı yok, sadece RAP'in Fiori'de ret gerekçesi giriş diyaloğunu render edebilmesi için var. |
| `ZBP_I_PR_HEADER` | Behavior (implementation) | Tüm BO için tek behavior implementasyon sınıfı: header'da beş determination, item'da üç, üç validation, dört action (`submit`/`approve`/`reject`/`requestInfo`), determine action `recalcTotal`, `get_instance_features`, `get_instance_authorizations`. |
| `ZC_PR_HEADER` / `ZC_PR_ITEM` | Projection | Tüketim view'ları ve projection behavior definition'ları. Composition/to-parent association'ı birbirine yönlendiriyor, UI'nin ihtiyaç duyduğu action'ları ve draft yönetimini yeniden açıyor, aşağıdaki metadata extension'ların interface view'lar yerine buraya eklenebilmesi için `@Metadata.allowExtensions: true` taşıyor. |
| `ZC_PR_HEADER_MDE` / `ZC_PR_ITEM_MDE` | Metadata Extension | Fiori Elements UI annotation'ları — facet'ler, field group'lar, line item'lar, status için `@UI.dataPoint`/`@UI.criticality`, submit/approve/reject/requestInfo için header toolbar butonları. |
| `ZUI_PR_HEADER` | Service | `ZC_PR_HEADER`'ı `PurchaseRequisition` olarak açan servis tanımı. `ZC_PR_ITEM`'a sadece `_Item` composition'ı üzerinden erişiliyor — hiçbir zaman tek başına açılmıyor. |

## 3. Bir talep sistemin içinden nasıl geçiyor

**Create → Draft → Submit:**

```
Fiori Elements uygulaması: kullanıcı "Create"a tıklıyor
    │
    ▼
yeni bir draft instance oluşturuluyor
    │
    ├─ determination setInitialStatus on modify { create; }  → Status = DRAFT
    ├─ determination setRequester on modify { create; }      → Requester = oturum açan kullanıcı
    │                                                           (cl_abap_context_info=>get_user_technical_name)
    ▼
kullanıcı Description, CostCenter'ı dolduruyor, satır kalemleri ekliyor
    │
    ▼
her yeni item için (association _Item { create; with draft; }):
    ├─ determination setItemNumber on modify { create; }
    │        → aynı header'ın kardeş item'ları arasındaki en yüksek numara, +10 artışla (10, 20, 30, ...)
    ├─ determination setItemCurrency on modify { create; }
    │        → Currency, parent header'dan kopyalanıyor
    └─ determination calculateItemAmount on modify { field Quantity, Price; }
             ├─ Amount = Quantity * Price
             └─ parent header üzerinde EXECUTE recalcTotal (EML, açıkça çağrılıyor)
                       └─ determination calculateTotal (always)  → TotalAmount = SUM(item Amount)
    │
    ▼
draft determine action Prepare  (Activate'ten önce otomatik çalışıyor)
    ├─ validation validateAmount        → TotalAmount sıfırdan büyük olmalı
    ├─ validation validateItems         → en az bir item gerekli
    └─ validation validateRejectReason  → sadece Status = REJECTED olduğunda devreye giriyor
    │
    ▼
draft action Activate optimized  → draft, aktif instance haline geliyor
    │
    ▼
kullanıcı "Submit"e tıklıyor  (action submit, sadece Status = DRAFT ya da INFO_REQ iken aktif)
    │
    ▼
ZBP_I_PR_HEADER=>submit  → Status = PENDING
    │
    ▼
determination setPRNumber on modify { field Status; }
    └─ sadece PrNumber IS INITIAL iken
          → cl_numberrange_runtime=>number_get( object = 'ZPR_RANGE', nr_range_nr = '01' )
```

**Onay akışı:**

```
Status = PENDING
    │
    ▼
get_instance_features (ZBP_I_PR_HEADER)
    ├─ %action-submit       → devre dışı  (zaten gönderildi)
    ├─ %action-approve      → aktif
    ├─ %action-reject       → aktif
    └─ %action-requestInfo  → aktif
    │
    ▼
onaylayan Object Page'i açıyor ve birini seçiyor:

    ├─ "Approve"  → action approve
    │        ▼
    │    ZBP_I_PR_HEADER=>approve  → Status = APPROVED
    │        ▼
    │    determination setApprovalData on modify { field Status; }
    │        └─ sadece Status = APPROVED ve Approver IS INITIAL iken
    │              → Approver = oturum açan kullanıcı, ApprovedAt = utclong_current( )
    │
    ├─ "Reject"  → action reject parameter ZA_PR_REJECT
    │        ▼
    │    ZBP_I_PR_HEADER=>reject  → Status = REJECTED, RejectReason = %param-reject_reason
    │        ▼
    │    validation validateRejectReason on save { field Status, RejectReason; }
    │        └─ Status = REJECTED ve RejectReason hâlâ boşsa kaydı bloklar
    │
    └─ "Request Info"  → action requestInfo
             ▼
         ZBP_I_PR_HEADER=>requestInfo  → Status = INFO_REQ
             ▼
         get_instance_features yeniden değerlendiriyor: %action-submit tekrar aktif,
         yani talep eden düzenleyip tekrar gönderebiliyor
```

## 4. Temel tasarım kararları

- **Durum akışı ve instance feature kontrolü** — talep beş durumdan geçiyor: `DRAFT` → `PENDING` → `APPROVED` / `REJECTED` / `INFO_REQ`. Hangi butonun mantıklı olduğunu UI'nin tahmin etmesine bırakmak yerine, `get_instance_features` her instance'ın güncel `Status`'unu okuyup her action'ın aktif/pasif durumunu açıkça belirliyor: `submit` sadece `Status = DRAFT` ya da `Status = INFO_REQ` iken aktif; `approve`, `reject` ve `requestInfo` sadece `Status = PENDING` iken aktif, diğer her durumda pasif. Bir taslağı onaylamayı imkansız kılan tüm mekanizma bu — `approve`'un içinde ayrıca bir kontrol yok, çünkü buton zaten hiç tıklanabilir hale gelmiyor.
- **Item numaralandırma** — `setItemNumber`, her yeni item'a create sırasında `ItemNumber`'ını atıyor. `_Item` association'ı üzerinden aynı header'ın kardeş item'larını okuyor, aralarındaki en yüksek numarayı buluyor ve üzerine 10 ekliyor (böylece item'lar 10, 20, 30, ... şeklinde sıralanıyor, klasik SAP dokümanlarındaki gibi araya sonradan bir şey eklenebilecek boşluk bırakılıyor). RAP, aynı header'a ait birden fazla yeni item'ı tek bir çağrıda determination'a verebildiği için — biri tek bir kayıtta üç satır eklediğinde — metod önce gelen key'leri her header için tek bir kayda indiriyor (`distinct_headers`), başlangıç numarasını hesaplamadan önce; böylece birlikte oluşturulan üç item aynı değere değil, ardışık numaralara düşüyor.
- **Para birimi mirası** — `setItemCurrency`, create sırasında çalışıyor ve parent header'ın `Currency`'sini `_Header` association'ı üzerinden okuyup yeni item'a kopyalıyor. `Price` ve `Amount`'un her item'da her zaman header'daki `TotalAmount` ile aynı para biriminde olmasını garanti eden şey bu — UI'de ya da API'de bir item'ın header'ın paylaşmadığı bir para biriminde kalabileceği hiçbir yol yok.
- **`PrNumber` için number range** — `setPRNumber`, okunabilir talep numarasını `cl_numberrange_runtime=>number_get` üzerinden `ZPR_RANGE` number range objesinden (range `01`) çekiyor. Bunu sadece `Status = PENDING` ve `PrNumber IS INITIAL` olan instance'lar için yapıyor — boşluk kontrolü, durum kontrolü kadar önemli, çünkü bu olmasaydı, `requestInfo` ile geri gönderilip tekrar submit edilen bir talep ikinci bir numara çeker ve ilkini sessizce sahipsiz bırakırdı.
- **Instance authorization bir placeholder** — `get_instance_authorizations` şu anda `%update`, `%delete` ve dört action için koşulsuz olarak `if_abap_behv=>auth-allowed` döndürüyor. Bu bilinçli, ve bu portfolyodaki diğer projelerin kendi eksik authority check'lerini belgelediği şekilde burada da belgeleniyor: bu, arkasında gerçek bir authorization objesi ya da PFCG rolü olmayan bir portfolyo projesi, dolayısıyla henüz karşılaştırılacak anlamlı bir şey yok. Gerçek bir devreye alım bunun yerine talep edenin ya da onaylayanın rolüne bağlı, en doğal olarak maliyet merkezi ya da organizasyon birimi bazında kapsamlanmış bir `AUTHORITY-CHECK` (ya da uygun bir RAP authorization check) koyardı.

## 5. CDS/database katmanı

- **`ZPR_HEADER`**, teknik anahtar `pr_uuid`'yi, iş anahtarı `pr_number`'ı, tanımlayıcı/organizasyonel alanları (`description`, `requester`, `cost_center`), tutar çiftini `total_amount`/`currency`, iş akışı alanı `status`'u, onay alanlarını `approver`/`approved_at`/`reject_reason`'ı ve RAP'in ihtiyaç duyduğu standart admin alanlarını (`created_by`/`created_at`, total ETag olarak `last_changed_by`/`last_changed_at`, optimistic concurrency için `local_last_changed_at`) taşıyor. **`ZPR_ITEM`** bu şekli satır kalemi seviyesinde tekrarlıyor: teknik anahtar olarak `item_uuid`, to-parent bağlantısı olarak `parent_uuid`, iş görünür satır numarası olarak `item_number`, `material`/`description`/`quantity`/`unit`, tutar çifti `price`/`amount` ile kendi `currency`'si, ve header ile aynı admin alanları.
- **`StatusCriticality`**, `ZI_PR_HEADER` üzerinde hesaplanan bir alan, kayıtlı bir kolon değil — serbest metin `Status` değerini 0-3 arası bir Fiori criticality koduna eşleyen bir `CASE` ifadesi (`DRAFT` için `0` none, `PENDING`/`INFO_REQ` için `2` warning, `APPROVED` için `3` positive, `REJECTED` için `1` negative). Sadece şu yüzden var: metadata extension'daki `@UI.criticality`, SAP'ın sabit criticality semantiğine sahip sayısal bir alana bağlanması gerekiyor — `'APPROVED'` gibi keyfi bir string üzerinde kendi başına dallanamıyor — yani bu alanın tek işi, Object Page'deki status göstergesine gerçekten renklendirebileceği bir şey vermek.

## 6. Bilinçli olarak basitleştirilenler

- **Draft tablo kaynak dosyaları yok** — `ZI_PR_HEADER.bdef` içinde `draft table zpr_header_d` / `draft table zpr_item_d` olarak adlandırılan `zpr_header_d` ve `zpr_item_d`, bu repodaki hiçbir yerde dosya olarak mevcut değil. Bu bir eksiklik değil, doğru olan bu: ADT, behavior definition aktive edildiği anda (doğrudan `with draft;` satırında sunulan Quick Fix üzerinden) bunları otomatik olarak üretiyor, ve yapıları tamamen persistence tablolarından ve RAP'in kendi draft yönetim alanlarından türetiliyor. Elle yazılacak ya da repoya eklenecek hiçbir şey yok.
- **Config tablosu yok, puanlama/ağırlıklandırma mantığı yok** — buradaki iş kuralları (açıklama ve maliyet merkezi zorunlu, en az bir item gerekli, toplam pozitif olmalı, bir ret gerekçe gerektiriyor) bir bakım tablosuna aktarılmak yerine doğrudan behavior definition'daki `field ( mandatory )` tanımları ve `ZBP_I_PR_HEADER`'daki `validation` metodları olarak ifade ediliyor. Bir onay iş akışının, bir risk puanlama motorunun sahip olduğu türden ayarlanabilir bir "hassasiyet"i yok — kuralın anlamını değiştirmeden yeniden ayarlanmak istenecek bir eşik yok — dolayısıyla bir tablo ve onu okuyacak bir sınıf eklemenin bir gerekçesi yoktu.
- **İzin verici instance authorization** — bkz. §4. `get_instance_authorizations`, istenen her operasyonu koşulsuz olarak veriyor; bu portfolyo projesinin arkasında olmayan gerçek bir authorization objesi için bir placeholder.
- **Sadece `ZC_PR_HEADER` servis olarak açık** — `ZUI_PR_HEADER` yalnızca `ZC_PR_HEADER`'ı açıyor. `ZC_PR_ITEM`'a sadece header'ın `_Item` composition'ı üzerinden erişilebiliyor, çünkü bu uygulamada bir kullanıcının item'lara, ait oldukları talebin dışında, tek başına gözatması ya da sorgulaması gereken bir senaryo yok.

## 7. Olası genişletmeler

- **Gerçek bir authorization objesi** — talep edenin ya da onaylayanın organizasyon birimine, ya da talebin kendi üzerindeki maliyet merkezine bağlı, `get_instance_authorizations`'taki izin verici placeholder'ın yerini alacak.
- **Workflow entegrasyonu** — onay adımını düz bir `approve`/`reject`/`requestInfo` action setinden SAP Business Workflow üzerinden yönlendirmeye taşımak; böylece onaylar behavior sınıfına gömülü sabit bir mantık olmadan devredilebilir, yükseltilebilir ya da tutara göre yönlendirilebilir.
- **ABAP Unit testleri** — determination'lar ve validation'lar doğal adaylar: `calculateItemAmount` ve `calculateTotal` basit girdi-çıktı hesaplamaları, `setItemNumber`'ın numaralandırma mantığının net sınır durumları var (ilk item, aynı anda oluşturulan birden fazla item), ve her validation metodunun karşı test edilebilecek açık bir geçme/kalma sınırı var.
- **Çok seviyeli onay** — ayarlanabilir bir `TotalAmount` eşiğinin üzerinde ikinci bir onaylayanı zorunlu kılmak; bu, durum modelini genişletmek (ara bir "kısmen onaylandı" durumu) ve verilen bir onayın gereken son onay olup olmadığına karar veren bir determination daha eklemek anlamına gelirdi.