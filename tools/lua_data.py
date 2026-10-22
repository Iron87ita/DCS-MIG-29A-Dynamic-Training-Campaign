"""Read serialized Lua data without executing embedded code; retain edit spans."""
import re, json
from dataclasses import dataclass

@dataclass
class Node:
    value: object
    start: int
    end: int
    children: dict | None = None

class Parser:
    def __init__(self, text): self.s=text; self.i=0
    def skip(self):
        while True:
            m=re.match(r'\s+|--\[\[[\s\S]*?\]\]|--[^\n]*', self.s[self.i:])
            if not m: break
            self.i+=len(m[0])
    def take(self, t):
        self.skip(); assert self.s.startswith(t,self.i),(self.i,self.s[self.i:self.i+100],t)
        self.i+=len(t)
    def string(self):
        q=self.s[self.i]; self.i+=1; out=[]
        while self.s[self.i]!=q:
            c=self.s[self.i]; self.i+=1
            if c=='\\':
                c=self.s[self.i]; self.i+=1
                if c.isdigit():
                    digits=c
                    while len(digits)<3 and self.s[self.i].isdigit(): digits+=self.s[self.i]; self.i+=1
                    c=chr(int(digits))
                elif c=='\r':
                    if self.s[self.i]=='\n': self.i+=1
                    c='\n'
                else: c={'n':'\n','r':'\r','t':'\t','a':'\a','b':'\b','f':'\f','v':'\v'}.get(c,c)
            out.append(c)
        self.i+=1; return ''.join(out)
    def value(self):
        self.skip(); start=self.i; c=self.s[self.i]
        if c=='{':
            self.i+=1; children={}; seq=1
            while True:
                self.skip()
                if self.s[self.i]=='}': self.i+=1; break
                if self.s[self.i]=='[':
                    self.i+=1; key=self.value().value; self.take(']'); self.take('=')
                else:
                    match=re.match(r'([A-Za-z_]\w*)\s*=',self.s[self.i:])
                    if match: key=match[1]; self.i+=len(match[0])
                    else: key=seq; seq+=1
                children[key]=self.value(); self.skip()
                if self.s[self.i] in ',;': self.i+=1
            return Node({k:v.value for k,v in children.items()},start,self.i,children)
        if c in '\"\'': v=self.string()
        else:
            match=re.match(r'-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|true\b|false\b|nil\b',self.s[self.i:])
            assert match,('Not serialized data',self.i,self.s[self.i:self.i+100])
            word=match[0]; self.i+=len(word)
            v={'true':True,'false':False,'nil':None}.get(word)
            if word not in ['true','false','nil']: v=float(word) if any(x in word for x in '.eE') else int(word)
        return Node(v,start,self.i)
    def assignment(self):
        self.skip(); match=re.match(r'\w+\s*=',self.s[self.i:]); assert match
        self.i+=len(match[0]); n=self.value(); self.skip(); assert self.i==len(self.s)
        return n

def dump(v):
    if isinstance(v,dict): return '{'+', '.join('['+dump(k)+'] = '+dump(x) for k,x in v.items())+'}'
    if isinstance(v,str): return '"'+v.replace('\\','\\\\').replace('"','\\"').replace('\r','\\r').replace('\n','\\n').replace('\t','\\t')+'"'
    if v is True: return 'true'
    if v is False: return 'false'
    if v is None: return 'nil'
    return str(v)

def patched(text, edits):
    for start,end,value in sorted(edits,reverse=True): text=text[:start]+dump(value)+text[end:]
    return text

def walk(node,path=()):
    yield path,node
    for k,v in (node.children or {}).items(): yield from walk(v,path+(k,))
