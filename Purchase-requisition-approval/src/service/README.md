# Service Layer

This folder holds the OData service definition `ZUI_PR_HEADER.srvd`, which exposes
`ZC_PR_HEADER` as the service — the composition child `ZC_PR_ITEM` is reached
automatically through the `_Item` association and isn't listed separately, since
this app has no standalone access to items outside the header.

You'll notice there is intentionally **no service binding file** here. In ABAP, a
service binding isn't a hand-written source file — it's an ADT (Eclipse) object that
you create visually, choose a protocol for (here: OData V4 - UI), and then publish.
Its activation/publish state lives in the system itself, not in a portable text file,
so committing one to Git wouldn't be meaningful or reusable.

To expose this service on a real system, follow the step-by-step instructions in
[docs/cds-odata-setup-guide.md](../../docs/cds-odata-setup-guide.md) — it covers
creating the service binding, choosing OData V4, publishing it, and previewing the
Fiori Elements app.

---

# Servis Katmanı

Bu klasör, `ZC_PR_HEADER`'ı servis olarak yayınlayan `ZUI_PR_HEADER.srvd` servis
tanımını içerir — composition child'ı olan `ZC_PR_ITEM`, `_Item` association'ı
üzerinden otomatik olarak erişilebilir olduğu için ayrıca listelenmiyor; bu
uygulamada item'lara header dışında bağımsız bir erişim planlanmıyor.

Burada kasıtlı olarak **service binding dosyası bulunmuyor**. ABAP'ta service binding
elle yazılan bir kaynak kod dosyası değildir; ADT (Eclipse) üzerinde görsel olarak
oluşturduğunuz, bir protokol seçtiğiniz (burada: OData V4 - UI) ve ardından publish
ettiğiniz bir nesnedir. Aktivasyon/publish durumu taşınabilir bir metin dosyasında
değil, doğrudan sistemde tutulur; bu yüzden Git'e böyle bir dosya eklemek anlamlı ya
da yeniden kullanılabilir olmaz.

Bu servisi gerçek bir sistemde yayınlamak için
[docs/cds-odata-setup-guide.md](../../docs/cds-odata-setup-guide.md) dosyasındaki
adım adım talimatları takip edin — service binding oluşturma, OData V4 seçimi,
publish etme ve Fiori Elements uygulamasını önizleme adımlarını kapsar.