use serde::Serialize;

#[derive(Clone, Serialize, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub enum Phase {
    Menu,
    Result,
    Sending,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: u64,
    pub input: String,
    pub output: Option<String>,
    pub phase: Phase,
    pub message: Option<String>,
}

#[derive(Default)]
pub struct Sessions {
    next_id: u64,
    pub current: Option<Session>,
}
impl Sessions {
    pub fn start(&mut self, input: String) -> bool {
        if self.current.is_some() {
            return false;
        }
        self.next_id += 1;
        self.current = Some(Session {
            id: self.next_id,
            input,
            output: None,
            phase: Phase::Menu,
            message: None,
        });
        true
    }
    pub fn get(&mut self, id: u64) -> Result<&mut Session, String> {
        self.current
            .as_mut()
            .filter(|s| s.id == id)
            .ok_or_else(|| "이미 종료된 호출입니다.".into())
    }
    pub fn transform(&mut self, id: u64) -> Result<(), String> {
        let s = self.get(id)?;
        if s.phase != Phase::Menu {
            return Err("변환할 수 없는 상태입니다.".into());
        }
        s.output = Some(s.input.replace("foo", "bar"));
        s.phase = Phase::Result;
        Ok(())
    }
    pub fn begin_send(&mut self, id: u64, original: bool) -> Result<String, String> {
        let s = self.get(id)?;
        if s.phase == Phase::Sending {
            return Err("이미 전달 중입니다.".into());
        }
        let text = if original {
            s.input.clone()
        } else {
            s.output.clone().ok_or("먼저 변환을 실행하세요.")?
        };
        s.phase = Phase::Sending;
        s.message = None;
        Ok(text)
    }
    pub fn cancel(&mut self, id: u64) -> Result<(), String> {
        self.get(id)?;
        self.current = None;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_unicode_and_whitespace() {
        let mut s = Sessions::default();
        s.start(" foo\r\n한글😀 foofood FOO\t".into());
        s.transform(1).unwrap();
        assert_eq!(
            s.get(1).unwrap().output.as_deref(),
            Some(" bar\r\n한글😀 barbard FOO\t")
        );
    }
    #[test]
    fn stale_commands_cannot_touch_new_session() {
        let mut s = Sessions::default();
        s.start("foo".into());
        s.cancel(1).unwrap();
        s.start("new".into());
        assert!(s.transform(1).is_err());
        assert!(s.cancel(1).is_err());
        assert_eq!(s.get(2).unwrap().input, "new");
    }
    #[test]
    fn rejects_overlap_and_duplicate_send() {
        let mut s = Sessions::default();
        assert!(s.start("foo".into()));
        assert!(!s.start("other".into()));
        assert!(s.begin_send(1, false).is_err());
        s.transform(1).unwrap();
        assert_eq!(s.begin_send(1, false).unwrap(), "bar");
        assert!(s.begin_send(1, false).is_err());
        assert!(s.transform(1).is_err());
        s.cancel(1).unwrap();
        assert!(s.current.is_none());
    }
    #[test]
    fn unchanged_and_empty_results_are_valid_text() {
        let mut s = Sessions::default();
        s.start("한글".into());
        s.transform(1).unwrap();
        assert_eq!(s.begin_send(1, false).unwrap(), "한글");
        s.cancel(1).unwrap();
        s.start(String::new());
        s.transform(2).unwrap();
        assert_eq!(s.begin_send(2, false).unwrap(), "");
    }
}
