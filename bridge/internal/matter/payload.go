// Package matter implements Matter onboarding payload parsing and the
// commissioning manager. QR payloads are "MT:" + base38-encoded 88-bit
// packed struct (Matter spec §5.1.3).
package matter

import (
	"fmt"
	"strings"
)

const base38Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-."

// OnboardingPayload is the decoded content of a Matter QR code.
type OnboardingPayload struct {
	Version       int    `json:"version"`
	VendorID      uint16 `json:"vendorId"`
	ProductID     uint16 `json:"productId"`
	Flow          int    `json:"commissioningFlow"`
	DiscoveryCaps int    `json:"discoveryCapabilities"`
	Discriminator int    `json:"discriminator"`
	Passcode      uint32 `json:"passcode"`
}

// ParseQR decodes an "MT:..." QR code payload.
func ParseQR(code string) (*OnboardingPayload, error) {
	code = strings.TrimSpace(code)
	if !strings.HasPrefix(code, "MT:") {
		return nil, fmt.Errorf("not a Matter QR payload (missing MT: prefix)")
	}
	packed, err := base38Decode(code[3:])
	if err != nil {
		return nil, err
	}
	if len(packed) < 11 {
		return nil, fmt.Errorf("payload too short: %d bytes", len(packed))
	}

	bits := bitReader{data: packed}
	p := &OnboardingPayload{
		Version:       int(bits.read(3)),
		VendorID:      uint16(bits.read(16)),
		ProductID:     uint16(bits.read(16)),
		Flow:          int(bits.read(2)),
		DiscoveryCaps: int(bits.read(8)),
		Discriminator: int(bits.read(12)),
		Passcode:      uint32(bits.read(27)),
	}
	if p.Passcode == 0 || p.Passcode > 99999998 {
		return nil, fmt.Errorf("invalid passcode %d", p.Passcode)
	}
	return p, nil
}

// base38Decode: each 5-char group encodes 3 bytes (first char is the least
// significant digit); trailing groups of 4 chars -> 2 bytes, 2 chars -> 1.
func base38Decode(s string) ([]byte, error) {
	var out []byte
	for start := 0; start < len(s); start += 5 {
		end := start + 5
		if end > len(s) {
			end = len(s)
		}
		chunk := s[start:end]
		var byteCount int
		switch len(chunk) {
		case 5:
			byteCount = 3
		case 4:
			byteCount = 2
		case 2:
			byteCount = 1
		default:
			return nil, fmt.Errorf("invalid base38 group length %d", len(chunk))
		}
		var value uint32
		for i := len(chunk) - 1; i >= 0; i-- {
			idx := strings.IndexByte(base38Alphabet, chunk[i])
			if idx < 0 {
				return nil, fmt.Errorf("invalid base38 character %q", chunk[i])
			}
			value = value*38 + uint32(idx)
		}
		for i := 0; i < byteCount; i++ {
			out = append(out, byte(value&0xff))
			value >>= 8
		}
	}
	return out, nil
}

// bitReader reads little-endian bit fields from a byte slice (LSB first).
type bitReader struct {
	data []byte
	pos  int
}

func (r *bitReader) read(n int) uint64 {
	var v uint64
	for i := 0; i < n; i++ {
		byteIdx := r.pos / 8
		bitIdx := r.pos % 8
		if byteIdx < len(r.data) && r.data[byteIdx]&(1<<bitIdx) != 0 {
			v |= 1 << i
		}
		r.pos++
	}
	return v
}
