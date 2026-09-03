use crate::error::{Error, Result};

const MAGIC: &[u8; 8] = b"WGRDNS1\0";
const MAX_RECORDS: usize = 128;
const MAX_VALUES: usize = 128;
const MAX_FIELD_BYTES: usize = 4_096;
const MAX_SNAPSHOT_BYTES: usize = 1024 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DnsRecord {
    pub(crate) service: String,
    pub(crate) servers: Vec<String>,
    pub(crate) search_domains: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DnsSnapshot {
    pub(crate) records: Vec<DnsRecord>,
}

impl DnsSnapshot {
    pub(crate) fn encode(&self) -> Result<Vec<u8>> {
        if self.records.is_empty() || self.records.len() > MAX_RECORDS {
            return Err(Error::software("DNS snapshot has an invalid record count"));
        }
        let mut bytes = Vec::new();
        bytes.extend_from_slice(MAGIC);
        push_count(&mut bytes, self.records.len())?;
        for record in &self.records {
            push_string(&mut bytes, &record.service)?;
            push_strings(&mut bytes, &record.servers)?;
            push_strings(&mut bytes, &record.search_domains)?;
        }
        if bytes.len() > MAX_SNAPSHOT_BYTES {
            return Err(Error::software("DNS snapshot exceeded its size limit"));
        }
        Ok(bytes)
    }

    pub(crate) fn decode(bytes: &[u8]) -> Result<Self> {
        if bytes.len() > MAX_SNAPSHOT_BYTES || !bytes.starts_with(MAGIC) {
            return Err(Error::software("DNS snapshot is invalid"));
        }
        let mut cursor = Cursor {
            bytes,
            offset: MAGIC.len(),
        };
        let record_count = cursor.read_count(MAX_RECORDS)?;
        if record_count == 0 {
            return Err(Error::software("DNS snapshot is empty"));
        }
        let mut records = Vec::with_capacity(record_count);
        for _ in 0..record_count {
            records.push(DnsRecord {
                service: cursor.read_string()?,
                servers: cursor.read_strings()?,
                search_domains: cursor.read_strings()?,
            });
        }
        if cursor.offset != bytes.len() {
            return Err(Error::software("DNS snapshot has trailing data"));
        }
        Ok(Self { records })
    }
}

pub(crate) fn parse_networksetup_values(output: &[u8]) -> Result<Vec<String>> {
    let text = std::str::from_utf8(output)
        .map_err(|_| Error::unavailable("network configuration output is not UTF-8"))?;
    if text.starts_with("There aren't any ") {
        return Ok(Vec::new());
    }
    if text.contains("** Error") {
        return Err(Error::unavailable("network configuration query failed"));
    }
    let values: Vec<String> = text
        .lines()
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();
    if values.is_empty() {
        return Err(Error::unavailable("network configuration output is empty"));
    }
    if values.len() > MAX_VALUES
        || values.iter().any(|value| {
            value.len() > MAX_FIELD_BYTES
                || value
                    .bytes()
                    .any(|byte| byte.is_ascii_control() && byte != b'\t')
        })
    {
        return Err(Error::unavailable(
            "network configuration output exceeded its limits",
        ));
    }
    Ok(values)
}

fn push_strings(bytes: &mut Vec<u8>, values: &[String]) -> Result<()> {
    if values.len() > MAX_VALUES {
        return Err(Error::software("DNS snapshot has too many values"));
    }
    push_count(bytes, values.len())?;
    for value in values {
        push_string(bytes, value)?;
    }
    Ok(())
}

fn push_string(bytes: &mut Vec<u8>, value: &str) -> Result<()> {
    if value.is_empty() || value.len() > MAX_FIELD_BYTES || value.bytes().any(|byte| byte == 0) {
        return Err(Error::software("DNS snapshot contains an invalid value"));
    }
    let length = u32::try_from(value.len())
        .map_err(|_| Error::software("DNS snapshot value is too large"))?;
    bytes.extend_from_slice(&length.to_be_bytes());
    bytes.extend_from_slice(value.as_bytes());
    Ok(())
}

fn push_count(bytes: &mut Vec<u8>, value: usize) -> Result<()> {
    let count =
        u32::try_from(value).map_err(|_| Error::software("DNS snapshot count is too large"))?;
    bytes.extend_from_slice(&count.to_be_bytes());
    Ok(())
}

struct Cursor<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl Cursor<'_> {
    fn read_u32(&mut self) -> Result<u32> {
        let end = self
            .offset
            .checked_add(4)
            .ok_or_else(|| Error::software("DNS snapshot offset overflowed"))?;
        let value = self
            .bytes
            .get(self.offset..end)
            .ok_or_else(|| Error::software("DNS snapshot ended unexpectedly"))?;
        self.offset = end;
        let value: [u8; 4] = value
            .try_into()
            .map_err(|_| Error::software("DNS snapshot integer is invalid"))?;
        Ok(u32::from_be_bytes(value))
    }

    fn read_count(&mut self, maximum: usize) -> Result<usize> {
        let count = usize::try_from(self.read_u32()?)
            .map_err(|_| Error::software("DNS snapshot count is invalid"))?;
        if count > maximum {
            return Err(Error::software("DNS snapshot count exceeded its limit"));
        }
        Ok(count)
    }

    fn read_string(&mut self) -> Result<String> {
        let length = self.read_count(MAX_FIELD_BYTES)?;
        if length == 0 {
            return Err(Error::software("DNS snapshot contains an empty value"));
        }
        let end = self
            .offset
            .checked_add(length)
            .ok_or_else(|| Error::software("DNS snapshot offset overflowed"))?;
        let value = self
            .bytes
            .get(self.offset..end)
            .ok_or_else(|| Error::software("DNS snapshot ended unexpectedly"))?;
        self.offset = end;
        let value = std::str::from_utf8(value)
            .map_err(|_| Error::software("DNS snapshot value is not UTF-8"))?;
        if value.bytes().any(|byte| byte == 0) {
            return Err(Error::software("DNS snapshot contains a null byte"));
        }
        Ok(value.to_owned())
    }

    fn read_strings(&mut self) -> Result<Vec<String>> {
        let count = self.read_count(MAX_VALUES)?;
        let mut values = Vec::with_capacity(count);
        for _ in 0..count {
            values.push(self.read_string()?);
        }
        Ok(values)
    }
}

#[cfg(test)]
mod tests {
    use super::{DnsRecord, DnsSnapshot, parse_networksetup_values};
    use crate::error::Result;

    #[test]
    fn snapshot_round_trips_without_line_based_escaping() -> Result<()> {
        let expected = DnsSnapshot {
            records: vec![DnsRecord {
                service: "Wi-Fi".into(),
                servers: vec!["192.0.2.1".into(), "2001:db8::1".into()],
                search_domains: vec!["example.test".into()],
            }],
        };
        let encoded = expected.encode()?;
        assert_eq!(DnsSnapshot::decode(&encoded)?, expected);
        Ok(())
    }

    #[test]
    fn rejects_truncated_and_trailing_snapshots() -> Result<()> {
        let snapshot = DnsSnapshot {
            records: vec![DnsRecord {
                service: "Wi-Fi".into(),
                servers: Vec::new(),
                search_domains: Vec::new(),
            }],
        };
        let encoded = snapshot.encode()?;
        assert!(DnsSnapshot::decode(&encoded[..encoded.len() - 1]).is_err());
        let mut trailing = encoded;
        trailing.push(0);
        assert!(DnsSnapshot::decode(&trailing).is_err());
        Ok(())
    }

    #[test]
    fn parses_automatic_and_explicit_networksetup_values() -> Result<()> {
        assert!(
            parse_networksetup_values(b"There aren't any DNS Servers set on Wi-Fi.\n")?.is_empty()
        );
        assert_eq!(
            parse_networksetup_values(b"192.0.2.1\n2001:db8::1\n")?,
            ["192.0.2.1", "2001:db8::1"]
        );
        Ok(())
    }
}
