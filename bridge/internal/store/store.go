// Package store persists devices in an embedded BoltDB file.
package store

import (
	"encoding/json"

	"github.com/mamoonk/omni-assistant/bridge/internal/device"
	bolt "go.etcd.io/bbolt"
)

var bucketDevices = []byte("devices")

type Store struct {
	db *bolt.DB
}

func Open(path string) (*Store, error) {
	db, err := bolt.Open(path, 0o600, nil)
	if err != nil {
		return nil, err
	}
	err = db.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists(bucketDevices)
		return err
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
