package matter

import "testing"

// The canonical connectedhomeip test payload: VID 0xFFF1, PID 0x8000,
// discriminator 3840, passcode 20202021 (verified by hand against the
// spec bit layout).
const chipTestQR = "MT:Y.K9042C00KA0648G00"

func TestParseQRKnownVector(t *testing.T) {
	p, err := ParseQR(chipTestQR)
	if err != nil {
		t.Fatal(err)
	}
	if p.Version != 0 {
		t.Errorf("version = %d, want 0", p.Version)
	}
	if p.VendorID != 0xFFF1 {
		t.Errorf("vendorId = %#x, want 0xFFF1", p.VendorID)
	}
	if p.ProductID != 0x8000 {
		t.Errorf("productId = %#x, want 0x8000", p.ProductID)
	}
	if p.Discriminator != 3840 {
		t.Errorf("discriminator = %d, want 3840", p.Discriminator)
	}
	if p.Passcode != 20202021 {
		t.Errorf("passcode = %d, want 20202021", p.Passcode)
	}
}

func TestParseQRRejectsGarbage(t *testing.T) {
	for _, bad := range []string{
		"",
		"HT:Y.K9042C00KA0648G00", // wrong prefix
		"MT:!!!",                 // invalid chars
		"MT:ABC",                 // invalid group length
		"MT:00",                  // too short
	} {
		if _, err := ParseQR(bad); err == nil {
			t.Errorf("ParseQR(%q) should fail", bad)
		}
	}
}
