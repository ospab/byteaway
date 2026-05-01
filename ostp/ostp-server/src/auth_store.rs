use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use uuid::Uuid;

pub struct AccessKeyStore {
    path: PathBuf,
    keys: Arc<RwLock<HashMap<String, ()>>>,
}

impl AccessKeyStore {
    pub fn load_or_create(path: PathBuf) -> Result<Self> {
        if !path.exists() {
            let mut initial = HashMap::new();
            initial.insert(Uuid::new_v4().to_string(), ());
            persist_keys(&path, &initial)?;
        }

        let content = fs::read_to_string(&path)
            .with_context(|| format!("failed to read access keys file {}", path.display()))?;

        let mut keys = HashMap::new();
        for line in content.lines() {
            let key = line.trim();
            if !key.is_empty() {
                keys.insert(key.to_string(), ());
            }
        }

        if keys.is_empty() {
            keys.insert(Uuid::new_v4().to_string(), ());
            persist_keys(&path, &keys)?;
        }

        Ok(Self {
            path,
            keys: Arc::new(RwLock::new(keys)),
        })
    }

    pub fn shared(&self) -> Arc<RwLock<HashMap<String, ()>>> {
        Arc::clone(&self.keys)
    }

    pub fn count(&self) -> usize {
        self.keys.read().map(|k| k.len()).unwrap_or(0)
    }

    pub fn create_new_key(&self) -> Result<String> {
        let new_key = Uuid::new_v4().to_string();
        {
            let mut guard = self
                .keys
                .write()
                .map_err(|_| anyhow::anyhow!("access keys lock poisoned"))?;
            guard.insert(new_key.clone(), ());
            persist_keys(&self.path, &guard)?;
        }
        Ok(new_key)
    }
}

fn persist_keys(path: &PathBuf, keys: &HashMap<String, ()>) -> Result<()> {
    let mut list: Vec<&String> = keys.keys().collect();
    list.sort();
    let mut content = String::new();
    for key in list {
        content.push_str(key);
        content.push('\n');
    }
    fs::write(path, content)
        .with_context(|| format!("failed to write access keys file {}", path.display()))
}
