package storage

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"sync"
)

// Store defines the interface for certificate storage
type Store interface {
	// Get retrieves data by key
	Get(key string) ([]byte, error)
	
	// Put stores data with the given key
	Put(key string, data []byte) error
	
	// Delete removes data with the given key
	Delete(key string) error
	
	// List returns all keys in the store
	List() ([]string, error)
}

// FileStore implements Store using the filesystem
type FileStore struct {
	dir string
	mu  sync.RWMutex
}

// NewFileStore creates a new file-based store
func NewFileStore(dir string) (*FileStore, error) {
	if dir == "" {
		return nil, errors.New("directory cannot be empty")
	}

	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("failed to create directory: %w", err)
	}

	return &FileStore{
		dir: dir,
	}, nil
}

// keyToPath converts a key to a filesystem path
func (fs *FileStore) keyToPath(key string) string {
	return filepath.Join(fs.dir, key)
}

// Get retrieves data by key
func (fs *FileStore) Get(key string) ([]byte, error) {
	fs.mu.RLock()
	defer fs.mu.RUnlock()

	path := fs.keyToPath(key)
	data, err := ioutil.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, fmt.Errorf("key %s not found", key)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}
	
	return data, nil
}

// Put stores data with the given key
func (fs *FileStore) Put(key string, data []byte) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()

	path := fs.keyToPath(key)
	if err := ioutil.WriteFile(path, data, 0600); err != nil {
		return fmt.Errorf("failed to write file: %w", err)
	}
	
	return nil
}

// Delete removes data with the given key
func (fs *FileStore) Delete(key string) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()

	path := fs.keyToPath(key)
	if err := os.Remove(path); err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to delete file: %w", err)
	}
	
	return nil
}

// List returns all keys in the store
func (fs *FileStore) List() ([]string, error) {
	fs.mu.RLock()
	defer fs.mu.RUnlock()

	files, err := os.ReadDir(fs.dir)
	if err != nil {
		return nil, fmt.Errorf("failed to read directory: %w", err)
	}

	keys := make([]string, 0, len(files))
	for _, file := range files {
		if !file.IsDir() {
			keys = append(keys, file.Name())
		}
	}
	
	return keys, nil
}

// MemoryStore implements Store using in-memory storage
type MemoryStore struct {
	data map[string][]byte
	mu   sync.RWMutex
}

// NewMemoryStore creates a new in-memory store
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		data: make(map[string][]byte),
	}
}

// Get retrieves data by key
func (ms *MemoryStore) Get(key string) ([]byte, error) {
	ms.mu.RLock()
	defer ms.mu.RUnlock()

	data, ok := ms.data[key]
	if !ok {
		return nil, fmt.Errorf("key %s not found", key)
	}
	
	return data, nil
}

// Put stores data with the given key
func (ms *MemoryStore) Put(key string, data []byte) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	ms.data[key] = data
	return nil
}

// Delete removes data with the given key
func (ms *MemoryStore) Delete(key string) error {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	delete(ms.data, key)
	return nil
}

// List returns all keys in the store
func (ms *MemoryStore) List() ([]string, error) {
	ms.mu.RLock()
	defer ms.mu.RUnlock()

	keys := make([]string, 0, len(ms.data))
	for k := range ms.data {
		keys = append(keys, k)
	}
	
	return keys, nil
}

// StoreConfig holds configuration for creating a store
type StoreConfig struct {
	Type string                 `json:"type" yaml:"type"`
	Path string                 `json:"path" yaml:"path"`
	Args map[string]interface{} `json:"args" yaml:"args"`
}

// NewStore creates a store based on the configuration
func NewStore(config StoreConfig) (Store, error) {
	switch config.Type {
	case "file":
		return NewFileStore(config.Path)
	case "memory":
		return NewMemoryStore(), nil
	default:
		return nil, fmt.Errorf("unknown store type: %s", config.Type)
	}
}