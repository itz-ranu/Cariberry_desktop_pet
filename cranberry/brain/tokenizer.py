"""A tiny word-level tokenizer, built from scratch on Cranberry's own corpus.

Word-level (rather than BPE) is the right call for a small, narrow-domain
dataset like ours: with only a few thousand training sentences there isn't
enough data to learn subword merges well, and every command word Cranberry
actually needs ("whatsapp", "cranberry", app names) is a single token anyway.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

PAD, UNK, BOS, EOS = "<pad>", "<unk>", "<bos>", "<eos>"
SPECIAL_TOKENS = [PAD, UNK, BOS, EOS]

# Word runs, OR any single non-word/non-space character as its own token --
# that second branch is what catches emoji (🐾💗🐕), em dashes, and other
# punctuation. Without it, anything outside [a-z0-9'.,!?] was silently
# dropped during tokenization, which meant Cariberry's emoji-heavy voice
# never actually reached the model: every 🐾/💗 in the training text vanished
# before training saw it, so the vocabulary had no emoji tokens to generate.
_WORD_RE = re.compile(r"[a-z0-9']+|[^\sa-z0-9']")


def basic_tokenize(text: str) -> list[str]:
    return _WORD_RE.findall(text.lower())


class Tokenizer:
    def __init__(self, vocab: list[str]):
        self.vocab = vocab
        self.token_to_id = {tok: i for i, tok in enumerate(vocab)}

    @classmethod
    def build(cls, corpus: list[str], min_freq: int = 1) -> "Tokenizer":
        counts: dict[str, int] = {}
        for line in corpus:
            for tok in basic_tokenize(line):
                counts[tok] = counts.get(tok, 0) + 1
        words = sorted([w for w, c in counts.items() if c >= min_freq])
        return cls(SPECIAL_TOKENS + words)

    def encode(self, text: str, add_special: bool = True) -> list[int]:
        ids = [self.token_to_id.get(tok, self.token_to_id[UNK]) for tok in basic_tokenize(text)]
        if add_special:
            ids = [self.token_to_id[BOS]] + ids + [self.token_to_id[EOS]]
        return ids

    def decode(self, ids: list[int]) -> str:
        words = [self.vocab[i] for i in ids if self.vocab[i] not in SPECIAL_TOKENS]
        text = " ".join(words)
        # Tidy up spacing before punctuation, e.g. "hi !" -> "hi!"
        return re.sub(r"\s+([.,!?])", r"\1", text)

    @property
    def pad_id(self) -> int:
        return self.token_to_id[PAD]

    @property
    def bos_id(self) -> int:
        return self.token_to_id[BOS]

    @property
    def eos_id(self) -> int:
        return self.token_to_id[EOS]

    def __len__(self) -> int:
        return len(self.vocab)

    def save(self, path: Path) -> None:
        path.write_text(json.dumps(self.vocab))

    @classmethod
    def load(cls, path: Path) -> "Tokenizer":
        return cls(json.loads(path.read_text()))
