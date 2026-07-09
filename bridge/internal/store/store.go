// Package store persists devices in an embedded BoltDB file.
package store

import (
	"encoding/json"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	bolt "go.etcd.io/bbolt"
)

var (
	bucketDevices     = []byte("devices")
	bucketAutomations = []byte("automations")
	bucketConfig      = []byte("config")
)

type Store struct {
	db *bolt.DB
}

func Open(path string) (*Store, error) {
	db, err := bolt.Open(path, 0o600, nil)
	if err != nil {
		return nil, err
	}
	err = db.Update(func(tx *bolt.Tx) error {
		for _, b := range [][]byte{bucketDevices, bucketAutomations, bucketConfig} {
			if _, err := tx.CreateBucketIfNotExists(b); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		db.Close()
		return nil, err
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) SaveDevice(d device.Device) error {
	raw, err := json.Marshal(d)
	if err != nil {
		return err
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(bucketDevices).Put([]byte(d.ID), raw)
	})
}

func (s *Store) DeleteDevice(id string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(bucketDevices).Delete([]byte(id))
	})
}

func (s *Store) SetConfig(key, value string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(bucketConfig).Put([]byte(key), []byte(value))
	})
}

func (s *Store) Config(key string) (string, error) {
	var value string
	err := s.db.View(func(tx *bolt.Tx) error {
		if v := tx.Bucket(bucketConfig).Get([]byte(key)); v != nil {
			value = string(v)
		}
		return nil
	})
	return value, err
}

// ReplaceAutomationsJSON stores the full synced rule set as one blob.
func (s *Store) ReplaceAutomationsJSON(raw []byte) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(bucketAutomations).Put([]byte("all"), raw)
	})
}

func (s *Store) AutomationsJSON() ([]byte, error) {
	var raw []byte
	err := s.db.View(func(tx *bolt.Tx) error {
		if v := tx.Bucket(bucketAutomations).Get([]byte("all")); v != nil {
			raw = append([]byte(nil), v...)
		}
		return nil
	})
	return raw, err
}

func (s *Store) Devices() ([]device.Device, error) {
	var devices []device.Device
	err := s.db.View(func(tx *bolt.Tx) error {
		return tx.Bucket(bucketDevices).ForEach(func(_, v []byte) error {
			var d device.Device
			if err := json.Unmarshal(v, &d); err != nil {
				return err
			}
			devices = append(devices, d)
			return nil
		})
	})
	return devices, err
}
