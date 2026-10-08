"""Trains Cranberry's brain: the intent classifier and the persona generator.

Run: python -m cranberry.brain.train

Both models start from random weights and are trained only on the synthetic
corpus in dataset_gen.py (no external data, no pretrained checkpoints). Feel
free to add your own lines to dataset_gen.py's template lists before
retraining — more phrasing variety there directly improves both models.
"""

from __future__ import annotations

import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset

from .. import config
from .dataset_gen import INTENTS, generate_chat_examples, generate_intent_examples
from .intent_classifier import IntentClassifier
from .model import TinyGPT
from .tokenizer import Tokenizer

MAX_LEN = 48
# Shared with infer.py, which needs the exact same architecture to load
# these weights back with load_state_dict -- keeping the numbers in one
# place avoids a silent shape-mismatch if only one side gets edited.
GENERATOR_D_MODEL = 160
GENERATOR_N_LAYERS = 5


def _pad(ids: list[int], length: int, pad_id: int) -> list[int]:
    if len(ids) >= length:
        return ids[:length]
    return ids + [pad_id] * (length - len(ids))


class IntentDataset(Dataset):
    def __init__(self, examples, tokenizer: Tokenizer):
        self.examples = examples
        self.tokenizer = tokenizer

    def __len__(self) -> int:
        return len(self.examples)

    def __getitem__(self, idx: int):
        example = self.examples[idx]
        ids = self.tokenizer.encode(example.text, add_special=False)
        ids = _pad(ids, MAX_LEN, self.tokenizer.pad_id)
        label = INTENTS.index(example.intent)
        return torch.tensor(ids), label


class ChatDataset(Dataset):
    """Trains on the full "user: ... cranberry: ..." sequence with standard
    next-token prediction. Simpler than masking the loss to only the reply
    span, and works fine at this scale since we sample starting after
    "cranberry:" at inference time anyway (see infer.py)."""

    def __init__(self, examples, tokenizer: Tokenizer):
        self.sequences = []
        for example in examples:
            text = f"user: {example.prompt} cranberry: {example.reply}"
            ids = tokenizer.encode(text, add_special=True)
            ids = _pad(ids, MAX_LEN, tokenizer.pad_id)
            self.sequences.append(ids)

    def __len__(self) -> int:
        return len(self.sequences)

    def __getitem__(self, idx: int):
        ids = self.sequences[idx]
        return torch.tensor(ids[:-1]), torch.tensor(ids[1:])


def train_intent_classifier(tokenizer: Tokenizer, examples) -> IntentClassifier:
    dataset = IntentDataset(examples, tokenizer)
    loader = DataLoader(dataset, batch_size=32, shuffle=True)

    model = IntentClassifier(vocab_size=len(tokenizer))
    optimizer = torch.optim.Adam(model.parameters(), lr=2e-3)
    loss_fn = nn.CrossEntropyLoss()

    print("Training intent classifier...")
    for epoch in range(1, 21):
        model.train()
        total_loss, correct, total = 0.0, 0, 0
        for tokens, labels in loader:
            optimizer.zero_grad()
            logits = model(tokens, tokenizer.pad_id)
            loss = loss_fn(logits, labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * len(labels)
            correct += (logits.argmax(dim=-1) == labels).sum().item()
            total += len(labels)
        print(f"  epoch {epoch}  loss={total_loss / total:.4f}  acc={correct / total:.2%}")
    return model


def train_generator(tokenizer: Tokenizer, examples) -> TinyGPT:
    dataset = ChatDataset(examples, tokenizer)
    loader = DataLoader(dataset, batch_size=32, shuffle=True)

    model = TinyGPT(vocab_size=len(tokenizer), d_model=GENERATOR_D_MODEL, n_layers=GENERATOR_N_LAYERS, max_len=MAX_LEN - 1)
    optimizer = torch.optim.Adam(model.parameters(), lr=3e-4)
    loss_fn = nn.CrossEntropyLoss(ignore_index=tokenizer.pad_id)

    print("Training persona generator...")
    for epoch in range(1, 81):
        model.train()
        total_loss, total_tokens = 0.0, 0
        for inputs, targets in loader:
            optimizer.zero_grad()
            logits = model(inputs)
            loss = loss_fn(logits.reshape(-1, logits.size(-1)), targets.reshape(-1))
            loss.backward()
            optimizer.step()
            non_pad = int((targets != tokenizer.pad_id).sum().item())
            total_loss += loss.item() * non_pad
            total_tokens += non_pad
        print(f"  epoch {epoch}  loss={total_loss / total_tokens:.4f}")
    return model


def main() -> None:
    intent_examples = generate_intent_examples()
    chat_examples = generate_chat_examples()

    corpus = [e.text for e in intent_examples]
    corpus += [f"user: {e.prompt} cranberry: {e.reply}" for e in chat_examples]
    tokenizer = Tokenizer.build(corpus)
    print(f"Vocabulary size: {len(tokenizer)}")

    intent_model = train_intent_classifier(tokenizer, intent_examples)
    generator = train_generator(tokenizer, chat_examples)

    config.WEIGHTS_DIR.mkdir(exist_ok=True)
    tokenizer.save(config.WEIGHTS_DIR / "vocab.json")
    torch.save(intent_model.state_dict(), config.WEIGHTS_DIR / "intent_classifier.pt")
    torch.save(generator.state_dict(), config.WEIGHTS_DIR / "generator.pt")
    print(f"\nSaved brain weights to {config.WEIGHTS_DIR}")


if __name__ == "__main__":
    main()
